const std = @import("std");

pub fn Either(L: type, R: type) type {
    return union(enum) {
        L: L,
        R: R,
    };
}

pub fn CowStr() type {
    return union(enum) {
        Borrowed: []const u8,
        Owned: []u8,

        pub fn deinit(self: *CowStr, alloc: std.mem.Allocator) void {
            switch (self.*) {
                .Owned => |o| {
                    alloc.free(o);
                },
                .Borrowed => {},
            }
        }

        pub fn borrowed(s: []const u8) CowStr {
            return .{ .Borrowed = s };
        }

        pub fn owned(alloc: std.mem.Allocator, s: []const u8) !CowStr {
            const o = try alloc.dupe(u8, s);
            return .{ .Owned = o };
        }

        pub fn get(self: *CowStr) []const u8 {
            return switch (self.*) {
                .Borrowed => |b| b,
                .Owned => |o| o,
            };
        }
    };
}
