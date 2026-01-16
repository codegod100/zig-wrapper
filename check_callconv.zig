const std = @import("std");

export fn zig_exported_test() i32 {
    return 21;
}

extern fn wry_test_simple() i32;

pub fn main() !void {
    std.debug.print("Checking callconv...\n", .{});

    // Call extern function
    const result = wry_test_simple();

    std.debug.print("Result: {} (expected 42)\n", .{result});
}
