const std = @import("std");
const wry = @import("wry.zig");

pub fn main() !void {
    // Create an arena allocator for test
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a webview with a URL (this BLOCKS until window closes)
    const url = "https://www.example.com";
    std.debug.print("Creating webview with URL: {s}\n", .{url});
    std.debug.print("Close the window to exit...\n", .{});

    var webview = try wry.WebView.init(allocator, url);
    defer webview.deinit();

    // Run event loop (blocking call in init(), this is no-op)
    std.debug.print("Waiting for window to close...\n", .{});
    webview.run();

    std.debug.print("Window closed, exiting...\n", .{});
}
