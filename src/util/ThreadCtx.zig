const std = @import("std");
const Self = @This();

mu: std.Thread.Mutex = .{},
cond: std.Thread.Condition = .{},
done: std.atomic.Value(bool) = .init(false),

pub fn signal(self: *Self) void {
    self.mu.lock();
    defer self.mu.unlock();

    self.cond.signal();
}

pub fn isDone(self: *Self) bool {
    return self.done.load(.seq_cst);
}

pub fn timedWait(self: *Self, timeout_ns: u64, comptime f: anytype, args: anytype) !void {
    self.mu.lock();
    defer self.mu.unlock();

    const start_time = std.time.nanoTimestamp();
    defer {
        const elapsed = std.time.nanoTimestamp() - start_time;
        std.log.debug("ThreadCtx.timedWait elapsed time: {d} ns", .{elapsed});
    }

    const t = try std.Thread.spawn(.{}, f, args);
    t.detach();

    try self.cond.timedWait(&self.mu, timeout_ns);
    self.done.store(true, .release);
}
