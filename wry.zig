const std = @import("std");

pub const WebViewWrapper = opaque {};

// Rust function declarations
extern fn wry_create_and_run(url: [*c]const u8) void;
extern fn wry_eval_js(script: [*c]const u8) void;

// Callback type for JavaScript evaluation from backend
const JSEvalCallback = *const fn(message: [:0]const u8) callconv(.C) void;
var eval_callback: ?JSEvalCallback = null;

pub fn setEvalCallback(callback: JSEvalCallback) void {
    eval_callback = callback;
}

/// Send message to frontend via JavaScript evaluation
pub fn sendToFrontend(allocator: std.mem.Allocator, js_code: []const u8) !void {
    const js_c = try allocator.dupeZ(u8, js_code);
    defer allocator.free(js_c);
    wry_eval_js(js_c);
}

// File entry structure
pub const FileEntry = struct {
    name: []const u8,
    is_dir: bool,
    size: ?u64,
};

/// List files in a directory
pub fn listFiles(allocator: std.mem.Allocator, path: []const u8) ![]FileEntry {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var entries = std.ArrayList(FileEntry).init(allocator);

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const file_path = try std.fs.path.join(allocator, &.{ path, entry.name });
        defer allocator.free(file_path);

        const stat = std.fs.cwd().statFile(file_path) catch |err| {
            std.debug.print("Warning: could not stat {s}: {}\n", .{ file_path, err });
            continue;
        };

        const file_entry = try allocator.create(FileEntry);
        file_entry.* = FileEntry{
            .name = try allocator.dupe(u8, entry.name),
            .is_dir = entry.kind == .directory,
            .size = if (entry.kind == .directory) null else stat.size,
        };

        try entries.append(file_entry.*);
    }

    // Sort: directories first, then files
    std.sort.insertion(FileEntry, entries.items, {}, struct {
        fn compare(_: void, a: FileEntry, b: FileEntry) std.math.Order {
            if (a.is_dir and !b.is_dir) return .lt;
            if (!a.is_dir and b.is_dir) return .gt;
            return std.mem.order(u8, a.name, b.name);
        }
    }.compare);

    return entries.toOwnedSlice();
}

// Backend API for file operations
const Backend = struct {
    pub fn handleRequest(allocator: std.mem.Allocator, request: [:0]const u8) !void {
        if (std.mem.startsWith(u8, request, "list-files:")) {
            const path = request["list-files:".len..];
            const files = try listFiles(allocator, path);
            defer {
                for (files) |file| {
                    allocator.free(file.name);
                }
                allocator.free(files);
            }

            // Convert files to JSON
            var json_array = std.ArrayList(u8).init(allocator);
            defer json_array.deinit();

            try json_array.append('[');
            for (files, 0..) |file, i| {
                if (i > 0) try json_array.append(',');

                try json_array.append('{');
                try json_array.writer().print("\"name\":\"{s}\",\"is_dir\":{}", .{ file.name, file.is_dir });
                if (file.size) |size| {
                    try json_array.writer().print(",\"size\":{}", .{size});
                }
                try json_array.append('}');
            }
            try json_array.append(']');

            const js_code = try std.fmt.allocPrintZ(allocator,
                \\window.__handleBackendResponse({{action: 'list-files', files: {s}}});
            , .{json_array.items});
            defer allocator.free(js_code);

            try sendToFrontend(allocator, js_code);
        }
    }
};

/// C callback wrapper
export fn zigEvalCallback(message: [*c]const u8) callconv(.C) void {
    const msg = std.mem.span(message);
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    Backend.handleRequest(arena.allocator(), msg) catch |err| {
        std.debug.print("Error handling backend request: {}\n", .{err});
    };
}

// Simple blocking webview API
pub const WebView = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, url: []const u8) !WebView {
        // Convert URL to C string
        const url_c = try allocator.dupeZ(u8, url);
        defer allocator.free(url_c);

        // Set up callback for backend communication
        setEvalCallback(zigEvalCallback);

        // Inject JavaScript to set up communication
        const inject_js =
            \\// Backend API for communication
            \\window.__wry_backend__ = {
            \\    listFiles: function(path) {
            \\        window.__zig_ipc__('list-files:' + path);
            \\    }
            \\};
            \\console.log('Backend API injected');
        ;
        // Note: We can't inject JS before the page loads in blocking mode
        // The frontend will handle this itself

        // Note: wry_create_and_run is BLOCKING - it won't return until window closes
        wry_create_and_run(url_c);

        return WebView{
            .allocator = allocator,
        };
    }

    pub fn run(self: *WebView) void {
        // No-op: blocking version runs everything in init()
        _ = self;
    }

    pub fn deinit(self: *WebView) void {
        // No-op: blocking version cleans up automatically
        _ = self;
    }
};
