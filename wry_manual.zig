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
            self.allocator.free(self.items);
            self.* = init(self.allocator);
        }

        pub fn append(self: *@This(), item: T) !void {
            try self.ensureTotalCapacity(self.items.len + 1);
            self.items[self.items.len] = item;
            self.items.len += 1;
        }

        fn ensureTotalCapacity(self: *@This(), new_capacity: usize) !void {
            if (self.capacity >= new_capacity) return;
            var better_capacity = self.capacity;
            while (better_capacity < new_capacity) {
                better_capacity += better_capacity / 2 + 8;
            }
            const new_items = try self.allocator.alloc(T, better_capacity);
            const byte_count = self.items.len * @sizeOf(T);
            @memcpy(new_items, self.items, byte_count);
            if (self.items.len > 0) {
                self.allocator.free(self.items);
            }
            self.items = new_items;
            self.capacity = better_capacity;
        }

        pub fn toOwnedSlice(self: *@This()) ![]T {
            const result = try self.allocator.alloc(T, self.items.len);
            const byte_count = self.items.len * @sizeOf(T);
            @memcpy(result, self.items, byte_count);
            return result;
        }
    };
}

// Rust function declarations
extern fn wry_create_and_run(url: [*c]const u8) void;

// File entry structure
pub const FileEntry = struct {
    name: []const u8,
    is_dir: bool,
    size: ?u64,
};

pub fn listFiles(allocator: std.mem.Allocator, path: []const u8) ![]FileEntry {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var entries = ArrayList(FileEntry).init(allocator);
    defer entries.deinit();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const file_path = try std.fs.path.join(allocator, &.{ path, entry.name });
        defer allocator.free(file_path);

        const stat = std.fs.cwd().statFile(file_path) catch |err| {
            std.debug.print("Warning: could not stat {s}: {}\\n", .{ file_path, err });
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
        fn lessThan(_: void, a: FileEntry, b: FileEntry) bool {
            if (a.is_dir and !b.is_dir) return true;
            if (!a.is_dir and b.is_dir) return false;
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lessThan);

    return try entries.toOwnedSlice(allocator);
}

// Simple blocking webview API
pub const WebView = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, url: []const u8) !WebView {
        // Convert URL to C string
        const url_c = try allocator.dupeZ(u8, url);
        defer allocator.free(url_c);

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

pub fn main() !void {
    // Create an arena allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Parse query parameters for directory path
    var dir_path: []const u8 = ".";
    const query = try parseQueryParams(allocator);
    if (query.get("dir")) |path| {
        dir_path = path;
    }
    defer if (query.get("dir")) |path| allocator.free(path);

    // Get absolute path to current directory
    const current_dir = try std.fs.cwd().realpathAlloc(allocator, dir_path);
    defer allocator.free(current_dir);

    // Get file list
    const files = try listFiles(allocator, dir_path);
    defer {
        for (files) |file| {
            allocator.free(file.name);
        }
        allocator.free(files);
    }

    // Build directory path parts for dropdown
    var accumulated_path = ArrayList(u8).init(allocator);
    defer accumulated_path.deinit(allocator);

    var path_parts = ArrayList(struct { name: []const u8, fullPath: []const u8 }).init(allocator);
    defer {
        for (path_parts.items) |p| {
            allocator.free(p.name);
            allocator.free(p.fullPath);
        }
        path_parts.deinit(allocator);
    }

    var it = std.mem.tokenizeScalar(u8, current_dir, std.fs.path.sep);
    while (it.next()) |part| {
        if (accumulated_path.items.len > 0) {
            try accumulated_path.append(allocator, std.fs.path.sep);
        }
        try accumulated_path.appendSlice(allocator, part);
        const full_path = try allocator.dupe(u8, accumulated_path.items);
        try path_parts.append(allocator, .{ .name = part, .fullPath = full_path });
    }

    // Generate file data JSON
    const json = try generateFileDataJSON(allocator, files, current_dir, path_parts.items);
    defer allocator.free(json);

    // Generate HTML with Preact and file data
    const html = try generateHTMLWithData(allocator, json);
    defer allocator.free(html);

    // Create zig-cache directory if it doesn't exist
    std.fs.cwd().makePath("zig-cache") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Write to temporary file
    const tmp_filename = "zig-cache/tmp_frontend.html";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp_filename, .data = html });

    // Construct file:// URL with query parameter
    const url = try std.fmt.allocPrint(allocator, "file://{s}/zig-cache/tmp_frontend.html?dir={s}", .{ current_dir, try std.uri.encodeComponent(current_dir) });
    defer allocator.free(url);

    std.debug.print("Creating webview with file list...\\n", .{});
    std.debug.print("Close window to exit...\\n", .{});

    var webview = try WebView.init(allocator, url);
    defer webview.deinit();

    std.debug.print("Waiting for window to close...\\n", .{});
    webview.run();

    std.debug.print("Window closed, exiting...\\n", .{});
}

fn parseQueryParams(allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
    const result = std.StringHashMap([]const u8).init(allocator);
    // For simplicity, we'll parse the URL from the file system in production
    return result;
}

fn generateFileDataJSON(allocator: std.mem.Allocator, files: []const FileEntry, current_dir: []const u8, path_parts: []const struct { name: []const u8, fullPath: []const u8 }) ![]u8 {
    var buffer = ArrayList(u8).init(allocator);
    defer buffer.deinit(allocator);

    try buffer.writer(allocator).print("{{\\n", .{});
    try buffer.writer(allocator).print("  \"currentPath\": \"{s}\",\\n", .{std.json.escapeString(allocator, current_dir)});
    try buffer.writer(allocator).print("  \"directoryPathParts\": [\\n", .{});

    for (path_parts, 0..) |part, i| {
        if (i > 0) try buffer.writer(allocator).print("    ,\\n", .{});
        try buffer.writer(allocator).print("    {{ \"name\": \"{s}\", \"fullPath\": \"{s}\" }}\\n", .{
            std.json.escapeString(allocator, part.name),
            std.json.escapeString(allocator, part.fullPath)
        });
    }

    try buffer.writer(allocator).print("  ],\\n", .{});
    try buffer.writer(allocator).print("  \"files\": [\\n", .{});

    for (files, 0..) |file, i| {
        if (i > 0) try buffer.writer(allocator).print("    ,\\n", .{});
        const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{current_dir, file.name});
        defer allocator.free(full_path);
        const size_str: []const u8 = if (file.size) |s|
            try std.fmt.allocPrint(allocator, "{d}", .{s})
        else
            "null";
        defer if (file.size != null) allocator.free(size_str);
        try buffer.writer(allocator).print("    {{ \"name\": \"{s}\", \"isDir\": {s}, \"size\": {s}, \"fullPath\": \"{s}\" }}\\n", .{
            std.json.escapeString(allocator, file.name),
            if (file.is_dir) "true" else "false",
            size_str,
            std.json.escapeString(allocator, full_path)
        });
    }

    try buffer.writer(allocator).print("  ]\\n", .{});
    try buffer.writer(allocator).print("}}\\n", .{});

    return try buffer.toOwnedSlice(allocator);
}

fn generateHTMLWithData(allocator: std.mem.Allocator, json_data: []const u8) ![]u8 {
    // Read HTML template file
    const template_path = try std.fs.path.join(allocator, &.{ ".", "html", "file_browser.html" });
    defer allocator.free(template_path);

    const template_content = try std.fs.cwd().readFileAlloc(allocator, template_path, 1024 * 1024);
    defer allocator.free(template_content);

    // Replace {{FILE_DATA}} placeholder with JSON data
    const placeholder = "{{FILE_DATA}}";
    const placeholder_index = std.mem.indexOf(u8, template_content, placeholder) orelse return error.PlaceholderNotFound;

    var html_buffer = ArrayList(u8).init(allocator);
    defer html_buffer.deinit(allocator);

    try html_buffer.appendSlice(allocator, template_content[0..placeholder_index]);
    try html_buffer.appendSlice(allocator, json_data);
    try html_buffer.appendSlice(allocator, template_content[placeholder_index + placeholder.len ..]);

    return try html_buffer.toOwnedSlice(allocator);
}
