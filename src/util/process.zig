const std = @import("std");
const mem = std.mem;
const ArrayList = std.ArrayList;
const Allocator = mem.Allocator;
const ChildProcess = std.process.Child;
const fs = std.fs;
const Ctx = @import("Ctx.zig");

/// Spawns a child process, waits for it, collecting stdout and stderr, and then returns.
/// If it succeeds, the caller owns result.stdout and result.stderr memory.
pub fn run(args: struct {
    ctx: Ctx,
    allocator: mem.Allocator,
    argv: []const []const u8,
    max_output_bytes: usize = 1024,
}) !std.process.Child.RunResult {
    var child = ChildProcess.init(args.argv, args.allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    var stdout: ArrayList(u8) = .empty;
    defer stdout.deinit(args.allocator);
    var stderr: ArrayList(u8) = .empty;
    defer stderr.deinit(args.allocator);

    try child.spawn();
    errdefer {
        _ = child.kill() catch {};
    }
    try collectOutput(args.ctx, child, args.allocator, &stdout, &stderr, args.max_output_bytes);

    return .{
        .stdout = try stdout.toOwnedSlice(args.allocator),
        .stderr = try stderr.toOwnedSlice(args.allocator),
        .term = try child.wait(),
    };
}

/// Collect the output from the process's stdout and stderr. Will return once all output
/// has been collected. This does not mean that the process has ended. `wait` should still
/// be called to wait for and clean up the process.
///
/// The process must be started with stdout_behavior and stderr_behavior == .Pipe
pub fn collectOutput(
    ctx: Ctx,
    child: ChildProcess,
    /// Used for `stdout` and `stderr`.
    allocator: Allocator,
    stdout: *ArrayList(u8),
    stderr: *ArrayList(u8),
    max_output_bytes: usize,
) !void {
    var poller = std.Io.poll(allocator, enum { stdout, stderr }, .{
        .stdout = child.stdout.?,
        .stderr = child.stderr.?,
    });
    defer poller.deinit();

    const stdout_r = poller.reader(.stdout);
    stdout_r.buffer = stdout.allocatedSlice();
    stdout_r.seek = 0;
    stdout_r.end = stdout.items.len;

    const stderr_r = poller.reader(.stderr);
    stderr_r.buffer = stderr.allocatedSlice();
    stderr_r.seek = 0;
    stderr_r.end = stderr.items.len;

    defer {
        stdout.* = .{
            .items = stdout_r.buffer[0..stdout_r.end],
            .capacity = stdout_r.buffer.len,
        };
        stderr.* = .{
            .items = stderr_r.buffer[0..stderr_r.end],
            .capacity = stderr_r.buffer.len,
        };
        stdout_r.buffer = &.{};
        stderr_r.buffer = &.{};
    }

    const timeout = ctx.ttl_ns();
    if (timeout <= 0) {
        return ctx.err().?;
    }
    while (try poller.pollTimeout(timeout)) {
        if (ctx.done()) {
            return ctx.err().?;
        }
        if (stdout_r.bufferedLen() > max_output_bytes)
            return error.StdoutStreamTooLong;
        if (stderr_r.bufferedLen() > max_output_bytes)
            return error.StderrStreamTooLong;
    }
}
