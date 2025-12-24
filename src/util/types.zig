const std = @import("std");

pub fn Either(L: type, R: type) type {
    return union(enum) {
        L: L,
        R: R,
    };
}

pub const ThreadContext = struct {
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    done: std.atomic.Value(bool) = .init(false),

    fn _run(self: *ThreadContext, comptime f: anytype, args: anytype) void {
        @call(.auto, f, args);

        self.mutex.lock();
        defer self.mutex.unlock();
        self.done.store(true, .release);
        self.cond.signal();
    }

    pub fn run(self: *ThreadContext, comptime f: anytype, args: anytype) !void {
        const t = try std.Thread.spawn(.{}, struct {
            fn ff(ctx: *ThreadContext, comptime func: anytype, func_args: anytype) void {
                ctx._run(func, func_args);
            }
        }.ff, .{ self, f, args });
        t.detach();
    }

    pub fn timedWait(self: *ThreadContext, timeout_ns: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.cond.timedWait(&self.mutex, timeout_ns);
    }

    pub fn isDone(self: *ThreadContext) bool {
        return self.done.load(.acquire);
    }
};
