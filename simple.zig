const std = @import("std");

pub fn main() !void {
    var list = std.ArrayList(u32).init(std.heap.page_allocator);
    defer list.deinit(std.heap.page_allocator);
    
    try list.append(std.heap.page_allocator, 1);
    try list.append(std.heap.page_allocator, 2);
    try list.append(std.heap.page_allocator, 3);
    
    for (list.items) |item| {
        std.debug.print("Item: {}\\n", .{item});
    }
}
