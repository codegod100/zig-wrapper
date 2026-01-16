const std = @import("std");
const wry = @import("wry.zig");

pub fn main() !void {
    // Create an arena allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get absolute path to current directory
    const current_dir = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(current_dir);

    // Generate HTML with embedded file list
    const html = try generateHTML(allocator, current_dir);

    // Create zig-cache directory if it doesn't exist
    std.fs.cwd().makePath("zig-cache") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Write to temporary file
    const tmp_filename = "zig-cache/tmp_frontend.html";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp_filename, .data = html });

    // Construct file:// URL
    const url = try std.fmt.allocPrint(allocator, "file://{s}/zig-cache/tmp_frontend.html", .{current_dir});

    std.debug.print("Creating webview...\n", .{});
    std.debug.print("Close window to exit...\n", .{});

    var webview = try wry.WebView.init(allocator, url);
    defer webview.deinit();

    std.debug.print("Waiting for window to close...\n", .{});
    webview.run();

    std.debug.print("Window closed, exiting...\n", .{});
}

fn generateHTML(allocator: std.mem.Allocator, base_path: []const u8) ![]u8 {
    _ = base_path; // unused parameter
    const files = try wry.listFiles(allocator, ".");
    defer {
        for (files) |file| {
            allocator.free(file.name);
        }
        allocator.free(files);
    }

    var html_buffer: std.ArrayListAligned(u8, null) = .empty;
    defer html_buffer.deinit(allocator);

    try html_buffer.appendSlice(allocator, "<!DOCTYPE html>\n");
    try html_buffer.appendSlice(allocator, "<html lang=\"en\">\n");
    try html_buffer.appendSlice(allocator, "<head>\n");
    try html_buffer.appendSlice(allocator, "<meta charset=\"UTF-8\">\n");
    try html_buffer.appendSlice(allocator, "<title>Wry Zig Wrapper</title>\n");
    try html_buffer.appendSlice(allocator, "<style>\n");
    try html_buffer.appendSlice(allocator, "body { font-family: sans-serif; padding: 20px; }\n");
    try html_buffer.appendSlice(allocator, "h1 { color: #667eea; }\n");
    try html_buffer.appendSlice(allocator, "ul { list-style: none; padding: 0; }\n");
    try html_buffer.appendSlice(allocator, "li { padding: 8px; border-bottom: 1px solid #eee; }\n");
    try html_buffer.appendSlice(allocator, "button { padding: 10px 20px; cursor: pointer; }\n");
    try html_buffer.appendSlice(allocator, "</style>\n");
    try html_buffer.appendSlice(allocator, "</head>\n");
    try html_buffer.appendSlice(allocator, "<body>\n");
    try html_buffer.appendSlice(allocator, "<h1>🚀 Wry Zig Wrapper</h1>\n");
    try html_buffer.appendSlice(allocator, "<p>Files in current directory:</p>\n");
    try html_buffer.appendSlice(allocator, "<ul>\n");

    for (files) |file| {
        const icon = if (file.is_dir) "📁" else "📄";
        const size_str = if (file.size) |s| try std.fmt.allocPrint(allocator, " ({d} bytes)", .{s}) else try std.fmt.allocPrint(allocator, "", .{});
        defer allocator.free(size_str);

        try html_buffer.writer(allocator).print("  <li>{s} {s}{s}</li>\n", .{ icon, file.name, size_str });
    }

    try html_buffer.appendSlice(allocator, "</ul>\n");
    try html_buffer.appendSlice(allocator, "<button onclick=\"window.location.reload()\">Refresh</button>\n");
    try html_buffer.appendSlice(allocator, "</body>\n");
    try html_buffer.appendSlice(allocator, "</html>\n");

    return try html_buffer.toOwnedSlice(allocator);
}
