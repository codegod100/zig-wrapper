const std = @import("std");

pub const WebViewWrapper = opaque {};

extern fn wry_test_simple() i32;
extern fn wry_test_with_param(x: i32) i32;
extern fn wry_test_string(output: [*c]u8, len: usize) i32;
extern fn wry_create_and_run(url: [*c]const u8) void;
extern fn wry_create_webview(url: [*c]const u8) ?*WebViewWrapper;
extern fn wry_run_event_loop(wrapper: *WebViewWrapper) void;
extern fn wry_evaluate_script(wrapper: *WebViewWrapper, script: [*c]const u8) c_int;
extern fn wry_set_url(wrapper: *WebViewWrapper, url: [*c]const u8) c_int;
extern fn wry_get_url(wrapper: *WebViewWrapper, buffer: [*c]u8, len: usize) c_int;
extern fn wry_set_event_callback(callback: EventCallback, user_data: *anyopaque) void;
extern fn wry_destroy_webview(wrapper: *WebViewWrapper) void;

// Event types for the callback
pub const EventType = enum(c_int) {
    CloseRequested = 1,
};

// Callback function type for webview events
pub const EventCallback = *const fn (event_type: EventType, user_data: *anyopaque) callconv(.C) void;

// Helper struct to manage the webview lifecycle
pub const WebView = struct {
    handle: *WebViewWrapper,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, url: []const u8) !WebView {
        const url_c = try allocator.dupeZ(u8, url);
        defer allocator.free(url_c);

        const handle = wry_create_webview(url_c) orelse return error.WebViewCreationFailed;

        return WebView{
            .handle = handle,
            .allocator = allocator,
        };
    }

    pub fn run(self: *WebView) void {
        wry_run_event_loop(self.handle);
    }

    pub fn evaluateScript(self: *WebView, script: []const u8) !void {
        const script_c = try self.allocator.dupeZ(u8, script);
        defer self.allocator.free(script_c);

        const result = wry_evaluate_script(self.handle, script_c);
        if (result != 0) {
            return error.ScriptEvaluationFailed;
        }
    }

    pub fn setUrl(self: *WebView, url: []const u8) !void {
        const url_c = try self.allocator.dupeZ(u8, url);
        defer self.allocator.free(url_c);

        const result = wry_set_url(self.handle, url_c);
        if (result != 0) {
            return error.UrlSetFailed;
        }
    }

    pub fn getUrl(self: *WebView) ![]const u8 {
        // First get the length
        var buffer: [1024]u8 = undefined;
        const len = wry_get_url(self.handle, &buffer, buffer.len);

        if (len < 0) {
            return error.GetUrlFailed;
        }

        // Copy the string
        const url_str = try self.allocator.dupe(u8, buffer[0..@intCast(len)]);
        return url_str;
    }

    pub fn deinit(self: *WebView) void {
        wry_destroy_webview(self.handle);
    }
};
