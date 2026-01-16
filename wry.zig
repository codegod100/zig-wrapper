const std = @import("std");

// Rust function declarations
extern fn wry_create_and_run(url: [*c]const u8) void;

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

    var entries: std.ArrayListAligned(FileEntry, null) = .empty;
    defer entries.deinit(allocator);

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

        try entries.append(allocator, file_entry.*);
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
