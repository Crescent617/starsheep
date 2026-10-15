const std = @import("std");

pub var DEBUG_MODE = false;

/// 进程级共享的 Io 实例。main 在最开始通过 setIo 设置；
/// 库代码（子进程执行、文件读写）统一通过 io() 获取。
/// 未设置时（如单元测试）惰性创建一个默认 Threaded 实现。
var io_instance: ?std.Io = null;
var io_fallback: ?*std.Io.Threaded = null;

pub fn init() void {
    DEBUG_MODE = getenv("STARSHEEP_DEBUG") != null;
}

pub fn setIo(instance: std.Io) void {
    io_instance = instance;
}

pub fn io() std.Io {
    if (io_instance) |i| return i;
    const t = std.heap.page_allocator.create(std.Io.Threaded) catch @panic("out of memory");
    t.* = .init(std.heap.page_allocator, .{});
    io_fallback = t;
    io_instance = t.io();
    return io_instance.?;
}

/// 读取环境变量。返回值指向进程环境，生命周期与进程一致，调用方不要 free。
pub fn getenv(comptime name: [:0]const u8) ?[]const u8 {
    const v = std.c.getenv(name) orelse return null;
    return std.mem.span(v);
}
