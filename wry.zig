const std = @import("std");

pub const WebViewWrapper = opaque {};

extern fn get_wry_test_simple() [*c]const u8;
extern fn wry_test_with_param(x: i32) i32;
extern fn wry_test_string(output: [*c]u8, len: usize) i32;
extern fn wry_create_and_run(url: [*c]const u8) void;

// Simple blocking webview API
pub const WebView = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, url: []const u8) !WebView {
        // Convert URL to C string
        const url_c = try allocator.dupeZ(u8, url);
        defer allocator.free(url_c);

        // Note: wry_create_and_run is BLOCKING - it won't return until window closes
        // This API is simpler but less flexible than non-blocking version
        wry_create_and_run(url_c);

        return WebView{
            .allocator = allocator,
        };
    }

    pub fn run(self: *WebView) void {
        // No-op: blocking version runs everything in init()
        _ = self;
    }

    pub fn evaluateScript(self: *WebView, script: []const u8) !void {
        // Not supported in blocking API version
        // JavaScript would need to be evaluated before blocking call
        _ = self;
        _ = script;
        return error.NotSupportedInBlockingMode;
    }

    pub fn deinit(self: *WebView) void {
        // No-op: blocking version cleans up automatically
        _ = self;
    }
};
