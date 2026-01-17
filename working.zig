const std = @import("std");

pub fn main() !void {
    var items: [10]u32 = undefined;
    var len: usize = 0;
    
    items[len] = 1;
    len += 1;
    items[len] = 2;
    len += 1;
    items[len] = 3;
    len += 1;
    
    for (items[0..len]) |item| {
        std.debug.print("Item: {}\\n", .{item});
    }
}
