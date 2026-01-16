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

    // Get file list
    const files = try wry.listFiles(allocator, ".");
    defer {
        for (files) |file| {
            allocator.free(file.name);
        }
        allocator.free(files);
    }

    // Generate HTML with file list
    const html = try generateHTML(allocator, files);
    defer allocator.free(html);

    // Create zig-cache directory if it doesn't exist
    std.fs.cwd().makePath("zig-cache") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Write to temporary file
    const tmp_filename = "zig-cache/tmp_frontend.html";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp_filename, .data = html });

    // Construct file:// URL
    const url = try std.fmt.allocPrint(allocator, "file://{s}/zig-cache/tmp_frontend.html", .{current_dir});
    defer allocator.free(url);

    std.debug.print("Creating webview with file list...\n", .{});
    std.debug.print("Close window to exit...\n", .{});

    var webview = try wry.WebView.init(allocator, url);
    defer webview.deinit();

    std.debug.print("Waiting for window to close...\n", .{});
    webview.run();

    std.debug.print("Window closed, exiting...\n", .{});
}

fn generateHTML(allocator: std.mem.Allocator, files: []const wry.FileEntry) ![]u8 {
    var html_buffer: std.ArrayListAligned(u8, null) = .empty;
    defer html_buffer.deinit(allocator);

    try html_buffer.appendSlice(allocator, "<!DOCTYPE html>\n");
    try html_buffer.appendSlice(allocator, "<html lang=\"en\">\n");
    try html_buffer.appendSlice(allocator, "<head>\n");
    try html_buffer.appendSlice(allocator, "<meta charset=\"UTF-8\">\n");
    try html_buffer.appendSlice(allocator, "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n");
    try html_buffer.appendSlice(allocator, "<title>File Browser</title>\n");
    try html_buffer.appendSlice(allocator, "<style>\n");
    try html_buffer.appendSlice(allocator, "    * { margin: 0; padding: 0; box-sizing: border-box; }\n");
    try html_buffer.appendSlice(allocator, "    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; padding: 20px; }\n");
    try html_buffer.appendSlice(allocator, "    .container { background: rgba(255, 255, 255, 0.95); border-radius: 20px; box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3); max-width: 800px; width: 100%; margin: 0 auto; overflow: hidden; }\n");
    try html_buffer.appendSlice(allocator, "    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; }\n");
    try html_buffer.appendSlice(allocator, "    .header h1 { margin: 0; font-size: 28px; font-weight: 700; }\n");
    try html_buffer.appendSlice(allocator, "    .header p { margin: 10px 0 0 0; opacity: 0.9; }\n");
    try html_buffer.appendSlice(allocator, "    .content { padding: 30px; max-height: 70vh; overflow-y: auto; }\n");
    try html_buffer.appendSlice(allocator, "    .file-list { list-style: none; padding: 0; margin: 0; }\n");
    try html_buffer.appendSlice(allocator, "    .file-item { display: flex; align-items: center; padding: 15px; border-bottom: 1px solid #e9ecef; transition: background 0.2s; cursor: pointer; }\n");
    try html_buffer.appendSlice(allocator, "    .file-item:hover { background: #f8f9fa; }\n");
    try html_buffer.appendSlice(allocator, "    .file-icon { font-size: 24px; margin-right: 15px; width: 40px; text-align: center; }\n");
    try html_buffer.appendSlice(allocator, "    .file-info { flex: 1; }\n");
    try html_buffer.appendSlice(allocator, "    .file-name { font-weight: 600; color: #495057; margin-bottom: 4px; }\n");
    try html_buffer.appendSlice(allocator, "    .file-meta { font-size: 12px; color: #6c757d; }\n");
    try html_buffer.appendSlice(allocator, "    .file-size { color: #667eea; }\n");
    try html_buffer.appendSlice(allocator, "</style>\n");
    try html_buffer.appendSlice(allocator, "</head>\n");
    try html_buffer.appendSlice(allocator, "<body>\n");
    try html_buffer.appendSlice(allocator, "    <div class=\"container\">\n");
    try html_buffer.appendSlice(allocator, "        <div class=\"header\">\n");
    try html_buffer.appendSlice(allocator, "            <h1>📁 File Browser</h1>\n");
    try html_buffer.appendSlice(allocator, "            <p>Files in current directory</p>\n");
    try html_buffer.appendSlice(allocator, "        </div>\n");
    try html_buffer.appendSlice(allocator, "        <div class=\"content\">\n");
    try html_buffer.appendSlice(allocator, "            <ul class=\"file-list\">\n");

    for (files) |file| {
        const icon = if (file.is_dir) "📁" else "📄";
        const size_str = if (file.size) |s| try std.fmt.allocPrint(allocator, "{d} bytes", .{s}) else "";
        defer if (file.size != null) allocator.free(size_str);

        try html_buffer.writer(allocator).print(
            \\                <li class="file-item">
            \\                    <div class="file-icon">{s}</div>
            \\                    <div class="file-info">
            \\                        <div class="file-name">{s}</div>
            \\                        <div class="file-meta">{s}</div>
            \\                    </div>
            \\                </li>
        , .{ icon, file.name, size_str });
    }

    try html_buffer.appendSlice(allocator, "            </ul>\n");
    try html_buffer.appendSlice(allocator, "        </div>\n");
    try html_buffer.appendSlice(allocator, "    </div>\n");
    try html_buffer.appendSlice(allocator, "</body>\n");
    try html_buffer.appendSlice(allocator, "</html>\n");

    return try html_buffer.toOwnedSlice(allocator);
}
