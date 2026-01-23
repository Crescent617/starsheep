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
