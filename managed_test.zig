const std = @import("std");

pub fn main() !void {
    var list = std.ArrayList(u32).Managed{};
    defer list.deinit();
    
    try list.append(1);
    try list.append(2);
    try list.append(3);
    
    for (list.items) |item| {
        std.debug.print("Item: {}\\n", .{item});
    }
}
