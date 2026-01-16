const std = @import("std");

// Define Rust function pointer type
const WryTestSimple = fn () callconv(.c) i32;

// Get function pointer at link time
extern fn get_wry_test_simple() [*c]const u8;

pub fn main() !void {
    std.debug.print("Testing via Rust wrapper...\n", .{});

    const func_ptr = get_wry_test_simple();
    if (func_ptr == null) {
        std.debug.print("Wrapper returned null!\n", .{});
        return error.NullFunctionPointer;
    }

    std.debug.print("Function pointer: {*}\n", .{func_ptr});

    const func: *const WryTestSimple = @ptrCast(func_ptr);

    std.debug.print("About to call function via pointer...\n", .{});

    const result = func();

    std.debug.print("Result: {} (expected 42)\n", .{result});
}
