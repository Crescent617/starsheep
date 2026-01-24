const std = @import("std");
const Self = @This();
pub const Err = error{DeadlineExceeded};
pub const root = Self{};

deadline_ns: i128 = std.math.maxInt(i128),
parent: ?*const Self = null,

pub fn withTimeout(parent: Self, timeout_ms: u64) Self {
    const now = std.time.nanoTimestamp();
    const ddl = now + @as(i128, timeout_ms) * std.time.ns_per_ms;
    return Self{
        .deadline_ns = @min(ddl, parent.deadline_ns),
        .parent = &parent,
    };
}

pub fn done(self: *const Self) bool {
    return std.time.nanoTimestamp() >= self.deadline_ns;
}

pub fn ttl_ns(self: *const Self) u64 {
    const diff = self.deadline_ns - std.time.nanoTimestamp();
    return if (diff > 0) @truncate(@as(u128, @intCast(diff))) else 0;
}

pub fn err(self: *const Self) ?Err {
    if (self.done()) {
        return Err.DeadlineExceeded;
    }
    return null;
}

test "withTimeout creates child with proper deadline" {
    const parent = Self{};
    const child = parent.withTimeout(100);
    try std.testing.expect(child.deadline_ns <= parent.deadline_ns);
    try std.testing.expect(child.parent != null);
}

test "done returns false for infinite deadline" {
    const ctx = Self{};
    try std.testing.expect(!ctx.done());
}

test "done returns true for expired deadline" {
    const ctx = Self{ .deadline_ns = 0 };
    try std.testing.expect(ctx.done());
}

test "ttl_ns returns positive for future deadline" {
    const ctx = Self{ .deadline_ns = std.math.maxInt(i128) };
    const ttl = ctx.ttl_ns();
    try std.testing.expect(ttl > 0);
}

test "ttl_ns returns 0 for past deadline" {
    const ctx = Self{ .deadline_ns = 0 };
    const ttl = ctx.ttl_ns();
    try std.testing.expectEqual(@as(u64, 0), ttl);
}

test "err returns null when not done" {
    const ctx = Self{};
    try std.testing.expectEqual(@as(?Err, null), ctx.err());
}

test "err returns DeadlineExceeded when done" {
    const ctx = Self{ .deadline_ns = 0 };
    const e = ctx.err() orelse return error.TestExpectedError;
    try std.testing.expectEqual(Err.DeadlineExceeded, e);
}
