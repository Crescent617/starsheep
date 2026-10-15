const std = @import("std");

const Once = @This();

const pending: u8 = 0;
const running: u8 = 1;
const done: u8 = 2;

state: std.atomic.Value(u8) = .init(pending),

/// 保证 f 在整个进程生命周期内只执行一次。
/// 并发调用时，其余调用方自旋等待首次执行完成。
pub fn call(self: *Once, comptime f: fn () void) void {
    if (self.state.load(.acquire) == done) return;
    while (true) {
        switch (self.state.load(.acquire)) {
            done => return,
            pending => {
                if (self.state.cmpxchgStrong(pending, running, .acq_rel, .acquire) == null) {
                    f();
                    self.state.store(done, .release);
                    return;
                }
            },
            else => std.atomic.spinLoopHint(),
        }
    }
}
