const std = @import("std");

// Manual ArrayList implementation to work around Zig 0.15.2 bug
pub fn ArrayList(comptime T: type) type {
    return struct {
        items: []T,
        capacity: usize,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .items = &[_]T{},
                .capacity = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            if (self.capacity > 0) {
                self.allocator.free(self.items.ptr[0..self.capacity]);
            }
            self.* = init(self.allocator);
        }

        pub fn append(self: *@This(), item: T) !void {
            try self.ensureTotalCapacity(self.items.len + 1);
            self.items.ptr[self.items.len] = item;
            self.items.len += 1;
        }

        pub fn appendSlice(self: *@This(), slice: []const T) !void {
            try self.ensureTotalCapacity(self.items.len + slice.len);
            @memcpy(self.items.ptr[self.items.len..][0..slice.len], slice.ptr);
            self.items.len += slice.len;
        }

        fn ensureTotalCapacity(self: *@This(), new_capacity: usize) !void {
            if (self.capacity >= new_capacity) return;
            var better_capacity = self.capacity;
            if (better_capacity == 0) better_capacity = 8;
            while (better_capacity < new_capacity) {
                better_capacity += better_capacity / 2 + 8;
            }
            const new_memory = try self.allocator.alloc(T, better_capacity);
            if (self.items.len > 0) {
                @memcpy(new_memory[0..self.items.len], self.items);
                self.allocator.free(self.items.ptr[0..self.capacity]);
            }
            self.items.ptr = new_memory.ptr;
            self.capacity = better_capacity;
        }

        pub fn toOwnedSlice(self: *@This()) ![]T {
            const result = try self.allocator.dupe(T, self.items);
            return result;
        }

        pub const Writer = std.io.GenericWriter(*@This(), error{OutOfMemory}, writeFn);

        fn writeFn(self: *@This(), bytes: []const u8) error{OutOfMemory}!usize {
            if (T != u8) @compileError("writer only supported for ArrayList(u8)");
            try self.appendSlice(bytes);
            return bytes.len;
        }

        pub fn writer(self: *@This()) Writer {
            return .{ .context = self };
        }
    };
}

// Rust function declarations
extern fn wry_create_and_run_with_ipc(url: [*c]const u8, callback: ?*const fn ([*c]const u8) callconv(.c) void) void;
extern fn wry_eval(js: [*c]const u8) void;

// File entry structure
pub const FileEntry = struct {
    name: []const u8,
    is_dir: bool,
    size: ?u64,
};

pub const PathPart = struct {
    name: []const u8,
    fullPath: []const u8,
};

pub fn listFiles(allocator: std.mem.Allocator, path: []const u8) ![]FileEntry {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
        std.debug.print("Error opening directory {s}: {any}\n", .{ path, err });
        return &[_]FileEntry{};
    };
    defer dir.close();

    var entries = ArrayList(FileEntry).init(allocator);
    defer entries.deinit();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const file_path = try std.fs.path.join(allocator, &.{ path, entry.name });

        const stat = std.fs.cwd().statFile(file_path) catch {
            // std.debug.print("Warning: could not stat {s}: {any}\n", .{ file_path, err });
            continue;
        };

        const file_entry = FileEntry{
            .name = try allocator.dupe(u8, entry.name),
            .is_dir = entry.kind == .directory,
            .size = if (entry.kind == .directory) null else stat.size,
        };

        try entries.append(file_entry);
    }

    // Sort: directories first, then files
    std.sort.insertion(FileEntry, entries.items, {}, struct {
        fn lessThan(_: void, a: FileEntry, b: FileEntry) bool {
            if (a.is_dir and !b.is_dir) return true;
            if (!a.is_dir and b.is_dir) return false;
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lessThan);

    return try entries.toOwnedSlice();
}

pub const WebView = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, url: []const u8, callback: ?*const fn ([*c]const u8) callconv(.c) void) !WebView {
        const url_c = try allocator.dupeZ(u8, url);
        wry_create_and_run_with_ipc(url_c, callback);
        return WebView{ .allocator = allocator };
    }

    pub fn run(self: *WebView) void { _ = self; }
    pub fn deinit(self: *WebView) void { _ = self; }
};

var global_arena: std.heap.ArenaAllocator = undefined;

export fn ipc_callback(msg: [*c]const u8) callconv(.c) void {
    const path = std.mem.span(msg);
    // std.debug.print("Navigating to: {s}\n", .{path});
    
    // Use a fresh arena for the refresh to avoid leaks in global scope
    var refresh_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer refresh_arena.deinit();
    const allocator = refresh_arena.allocator();

    const current_dir = std.fs.cwd().realpathAlloc(allocator, path) catch path;
    const files = listFiles(allocator, current_dir) catch return;

    var accumulated_path = ArrayList(u8).init(allocator);
    var path_parts = ArrayList(PathPart).init(allocator);

    var it = std.mem.tokenizeScalar(u8, current_dir, std.fs.path.sep);
    // On Unix, absolute paths start with / which tokenize removes. We need to add it back.
    if (std.fs.path.sep == '/') {
        accumulated_path.append('/') catch {};
    }
    
    while (it.next()) |part| {
        if (accumulated_path.items.len > 1) { // > 1 to account for leading /
            accumulated_path.append(std.fs.path.sep) catch break;
        }
        accumulated_path.appendSlice(part) catch break;
        const full_path = allocator.dupe(u8, accumulated_path.items) catch break;
        path_parts.append(.{ .name = part, .fullPath = full_path }) catch break;
    }

    const json = generateFileDataJSON(allocator, files, current_dir, path_parts.items) catch return;
    
    // Create the JS to update the state
    const js = std.fmt.allocPrint(allocator, "window.dispatchEvent(new CustomEvent('FILE_DATA_UPDATE', {{ detail: {s} }}));", .{json}) catch return;
    const js_c = allocator.dupeZ(u8, js) catch return;
    
    wry_eval(js_c);
}

pub fn main() !void {
    global_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer global_arena.deinit();
    const allocator = global_arena.allocator();

    const dir_path: []const u8 = ".";
    const current_dir = try std.fs.cwd().realpathAlloc(allocator, dir_path);
    const files = try listFiles(allocator, dir_path);

    var accumulated_path = ArrayList(u8).init(allocator);
    defer accumulated_path.deinit();

    var path_parts = ArrayList(PathPart).init(allocator);
    defer path_parts.deinit();

    var it = std.mem.tokenizeScalar(u8, current_dir, std.fs.path.sep);
    // On Unix, absolute paths start with / which tokenize removes. We need to add it back.
    if (std.fs.path.sep == '/') {
        try accumulated_path.append('/');
    }

    while (it.next()) |part| {
        if (accumulated_path.items.len > 1) {
            try accumulated_path.append(std.fs.path.sep);
        }
        try accumulated_path.appendSlice(part);
        const full_path = try allocator.dupe(u8, accumulated_path.items);
        try path_parts.append(.{ .name = part, .fullPath = full_path });
    }

    const json = try generateFileDataJSON(allocator, files, current_dir, path_parts.items);
    const html = try generateHTMLWithData(allocator, json);

    std.debug.print("Creating webview with file list...\n", .{});
    // Pass HTML content directly
    var webview = try WebView.init(allocator, html, ipc_callback);
    defer webview.deinit();
    webview.run();
}

fn generateFileDataJSON(allocator: std.mem.Allocator, files: []const FileEntry, current_dir: []const u8, path_parts: []const PathPart) ![]u8 {
    const FileInfo = struct {
        name: []const u8,
        isDir: bool,
        size: ?u64,
        fullPath: []const u8,
    };
    const Data = struct {
        currentPath: []const u8,
        directoryPathParts: []const PathPart,
        files: []const FileInfo,
    };

    var files_info = ArrayList(FileInfo).init(allocator);
    for (files) |file| {
        const full_path = try std.fs.path.join(allocator, &.{current_dir, file.name});
        try files_info.append(.{
            .name = file.name,
            .isDir = file.is_dir,
            .size = file.size,
            .fullPath = full_path,
        });
    }

    const data = Data{
        .currentPath = current_dir,
        .directoryPathParts = path_parts,
        .files = files_info.items,
    };

    var buffer = ArrayList(u8).init(allocator);
    try buffer.writer().print("{f}", .{std.json.fmt(data, .{})});
    return try buffer.toOwnedSlice();
}

fn generateHTMLWithData(allocator: std.mem.Allocator, json_data: []const u8) ![]u8 {
    const template_path = try std.fs.path.join(allocator, &.{ ".", "html", "file_browser.html" });
    const template_content = try std.fs.cwd().readFileAlloc(allocator, template_path, 1024 * 1024);

    const placeholder = "{{FILE_DATA}}";
    const placeholder_index = std.mem.indexOf(u8, template_content, placeholder) orelse return error.PlaceholderNotFound;

    var result = ArrayList(u8).init(allocator);
    try result.appendSlice(template_content[0..placeholder_index]);
    try result.appendSlice(json_data);
    try result.appendSlice(template_content[placeholder_index + placeholder.len ..]);

    return try result.toOwnedSlice();
}
