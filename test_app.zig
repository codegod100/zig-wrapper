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

    // Construct file:// URL to HTML (add null terminator)
    var html_buffer: [512]u8 = undefined;
    const html_path = try std.fmt.bufPrintZ(&html_buffer, "file://{s}/html/index.html", .{current_dir});

    std.debug.print("Creating webview with HTML frontend...\n", .{});
    std.debug.print("HTML path: {s}\n", .{html_path});
    std.debug.print("Close window to exit...\n", .{});

    var webview = try wry.WebView.init(allocator, html_path);
    defer webview.deinit();

    // Run event loop (blocking call in init(), this is no-op)
    std.debug.print("Waiting for window to close...\n", .{});
    webview.run();

    std.debug.print("Window closed, exiting...\n", .{});
}
