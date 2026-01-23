const std = @import("std");
const Ctx = @import("../util/Ctx.zig");

pub fn username(_: Ctx, alloc: std.mem.Allocator) []const u8 {
    if (!std.process.hasEnvVarConstant("SSH_CONNECTION")) {
        return "";
    }
    return std.process.getEnvVarOwned(alloc, "USER") catch "";
}

pub fn hostname(_: Ctx, alloc: std.mem.Allocator) []const u8 {
    if (!std.process.hasEnvVarConstant("SSH_CONNECTION")) {
        return "";
    }
    var buf: [std.c.HOST_NAME_MAX]u8 = undefined;
    // std.posix.gethostname 在各平台通用
    const name = std.posix.gethostname(&buf) catch "";
    return alloc.dupe(u8, name) catch "";
}
