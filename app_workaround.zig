const std = @import("std");

extern fn wry_create_and_run(url: [*c]const u8) void;

pub const FileEntry = struct {
    name: []const u8,
    is_dir: bool,
    size: ?u64,
};

pub fn listFiles(allocator: std.mem.Allocator, path: []const u8) ![]FileEntry {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    // Use fixed size array instead of ArrayList
    var files: [1000]FileEntry = undefined;
    var count: usize = 0;

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (count >= files.len) break;
        
        const file_path = try std.fs.path.join(allocator, &.{ path, entry.name });
        defer allocator.free(file_path);

        const stat = std.fs.cwd().statFile(file_path) catch |err| {
            std.debug.print("Warning: could not stat {s}: {}\\n", .{ file_path, err });
            continue;
        };

        files[count] = FileEntry{
            .name = try allocator.dupe(u8, entry.name),
            .is_dir = entry.kind == .directory,
            .size = if (entry.kind == .directory) null else stat.size,
        };
        count += 1;
    }

    // Sort: directories first, then files
    std.sort.insertion(FileEntry, files[0..count], {}, struct {
        fn lessThan(_: void, a: FileEntry, b: FileEntry) bool {
            if (a.is_dir and !b.is_dir) return true;
            if (!a.is_dir and b.is_dir) return false;
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lessThan);

    // Copy to owned slice
    const result = try allocator.alloc(FileEntry, count);
    for (files[0..count], 0..) |item, i| {
        result[i] = item;
    }
    return result;
}

pub const WebView = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, url: []const u8) !WebView {
        const url_c = try allocator.dupeZ(u8, url);
        defer allocator.free(url_c);
        wry_create_and_run(url_c);
        return WebView{ .allocator = allocator };
    }

    pub fn run(self: *WebView) void { _ = self; }
    pub fn deinit(self: *WebView) void { _ = self; }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const dir_path: []const u8 = ".";
    const current_dir = try std.fs.cwd().realpathAlloc(allocator, dir_path);
    defer allocator.free(current_dir);

    const files = try listFiles(allocator, dir_path);
    defer {
        for (files) |file| allocator.free(file.name);
        allocator.free(files);
    }

    // Simple JSON generation
    var json_buf: [8192]u8 = undefined;
    var json_len: usize = 0;

    const json_start = "{{\"currentPath\":\"{s}\",\"directoryPathParts\":[", .{std.json.escapeString(allocator, current_dir)};
    const json_start_len = std.mem.len(json_start);
    @memcpy(json_buf[json_len..][0..json_start_len], json_start);

    // Add current directory as option
    const current_opt = "\"{s}\",", .{std.json.escapeString(allocator, current_dir)};
    const current_opt_len = std.mem.len(current_opt);
    @memcpy(json_buf[json_len..][0..current_opt_len], current_opt);
    json_len += json_start_len + current_opt_len;

    // Write JSON and HTML
    const json_end = "],\"files\":[]}";
    const json_end_len = std.mem.len(json_end);
    @memcpy(json_buf[json_len..][0..json_end_len], json_end);
    json_len += json_end_len;

    const template_path = try std.fs.path.join(allocator, &.{ ".", "html", "file_browser.html" });
    defer allocator.free(template_path);
    const template_content = try std.fs.cwd().readFileAlloc(allocator, template_path, 1024 * 1024);
    defer allocator.free(template_content);

    const placeholder = "{{FILE_DATA}}";
    const placeholder_index = std.mem.indexOf(u8, template_content, placeholder) orelse return error.PlaceholderNotFound;

    const html_filename = "zig-cache/tmp_frontend.html";
    std.fs.cwd().makePath("zig-cache") catch {};
    
    var html_buf: [100000]u8 = undefined;
    @memcpy(html_buf[0..placeholder_index], template_content[0..placeholder_index]);
    @memcpy(html_buf[placeholder_index..][0..json_len], json_buf[0..json_len]);
    const template_after = template_content[placeholder_index + placeholder.len ..];
    const template_after_len = template_content.len - placeholder_index - placeholder.len;
    @memcpy(html_buf[placeholder_index + json_len ..][0..template_after_len], template_after);
    
    try std.fs.cwd().writeFile(.{ .sub_path = html_filename, .data = html_buf[0 .. placeholder_index + json_len + template_after_len] });

    const url = try std.fmt.allocPrint(allocator, "file://{s}/zig-cache/tmp_frontend.html?dir={s}", .{ current_dir, try std.uri.encodeComponent(current_dir) });
    defer allocator.free(url);

    std.debug.print("Creating webview...\\n", .{});
    var webview = try WebView.init(allocator, url);
    defer webview.deinit();
    webview.run();
    std.debug.print("Done!\\n", .{});
}
