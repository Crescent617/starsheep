const std = @import("std");
const chameleon = @import("chameleon");

pub fn format(alloc: std.mem.Allocator, _: ?[]const u8, out: []const u8) ![]const u8 {
    return alloc.dupe(u8, out);
}
