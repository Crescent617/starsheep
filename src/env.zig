const std = @import("std");

pub var DEBUG_MODE = false;

/// Process-wide Io interface, set once from main via `init`.
/// zig 0.16 removed global env/args/io, so we keep them here after startup.
pub var io: std.Io = undefined;

/// Process-wide environment block, set once from main via `init`.
pub var environ: std.process.Environ = undefined;

pub fn init(init_: std.process.Init) void {
    io = init_.io;
    environ = init_.minimal.environ;
    DEBUG_MODE = hasEnv("STARSHEEP_DEBUG");
}

/// Test-only initialization: test runners have no `std.process.Init`, so
/// build the environ from libc (starsheep always links libc) and use
/// `std.testing.io`.
pub fn initForTest() void {
    io = std.testing.io;
    environ = .{ .block = .{ .slice = std.c.environ } };
}

pub fn hasEnv(key: []const u8) bool {
    return std.process.Environ.getPosix(environ, key) != null;
}

/// Returns an owned copy of the env var value, or null when unset.
/// Caller owns the returned slice.
pub fn getEnvAlloc(alloc: std.mem.Allocator, key: []const u8) ?[]const u8 {
    return std.process.Environ.getAlloc(environ, alloc, key) catch null;
}

/// Replacement for the removed std.time.milliTimestamp().
pub fn milliTimestamp() i64 {
    const ts = std.Io.Clock.real.now(io);
    return @intCast(@divTrunc(ts.nanoseconds, std.time.ns_per_ms));
}
