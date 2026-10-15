const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Ctx = @import("Ctx.zig");
const env = @import("../env.zig");

pub const RunResult = struct {
    stdout: []u8,
    stderr: []u8,
    term: std.process.Child.Term,
};

/// Spawns a child process, waits for it, collecting stdout and stderr, and then returns.
/// If it succeeds, the caller owns result.stdout and result.stderr memory.
/// 超过 ctx 截止时间后会 kill 子进程并返回 ctx 的错误。
pub fn run(args: struct {
    ctx: Ctx,
    allocator: mem.Allocator,
    argv: []const []const u8,
    max_output_bytes: usize = 1024,
}) !RunResult {
    const io = env.io();

    var child = try std.process.spawn(io, .{
        .argv = args.argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    // 看门狗线程：到达截止时间后 kill 子进程，
    // 使管道 EOF、读取协程结束、wait 返回，整体按超时路径退出
    var finished = std.atomic.Value(bool).init(false);
    const ttl = args.ctx.ttl_ns();
    const watchdog: ?std.Thread = if (ttl > 0 and ttl < std.time.ns_per_day)
        std.Thread.spawn(.{}, watchdogMain, .{ &child, io, ttl, &finished }) catch null
    else
        null;
    defer if (watchdog) |t| t.join();

    var stdout_res: ReadResult = .{};
    var stderr_res: ReadResult = .{};
    var group: std.Io.Group = .init;
    group.async(io, readToEnd, .{ io, child.stdout.?, args.allocator, args.max_output_bytes, &stdout_res });
    group.async(io, readToEnd, .{ io, child.stderr.?, args.allocator, args.max_output_bytes, &stderr_res });
    try group.await(io);

    const term = try child.wait(io);
    finished.store(true, .release);

    if (stdout_res.err) |err| {
        args.allocator.free(stdout_res.bytes);
        args.allocator.free(stderr_res.bytes);
        return err;
    }
    if (stderr_res.err) |err| {
        args.allocator.free(stdout_res.bytes);
        args.allocator.free(stderr_res.bytes);
        return err;
    }
    if (args.ctx.err()) |err| {
        args.allocator.free(stdout_res.bytes);
        args.allocator.free(stderr_res.bytes);
        return err;
    }

    return .{
        .stdout = stdout_res.bytes,
        .stderr = stderr_res.bytes,
        .term = term,
    };
}

const ReadResult = struct {
    bytes: []u8 = &.{},
    err: ?anyerror = null,
};

/// 读管道直到 EOF。子进程被 kill 后管道自然 EOF，此函数随之返回。
fn readToEnd(io: std.Io, file: std.Io.File, allocator: Allocator, max_bytes: usize, out: *ReadResult) std.Io.Cancelable!void {
    var buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &buf);
    // 允许恰好 max_bytes；超出则 allocRemaining 报 StreamTooLong
    out.bytes = fr: {
        const bytes = file_reader.interface.allocRemaining(allocator, .limited(max_bytes + 1)) catch |err| {
            out.err = err;
            return;
        };
        break :fr bytes;
    };
}

fn watchdogMain(child: *std.process.Child, io: std.Io, ttl_ns: u64, finished: *std.atomic.Value(bool)) void {
    std.Io.sleep(io, .{ .nanoseconds = @intCast(ttl_ns) }, .awake) catch {};
    if (!finished.load(.acquire)) {
        child.kill(io);
    }
}
