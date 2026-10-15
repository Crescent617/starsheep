const std = @import("std");
const env = @import("../env.zig");
const Ctx = @import("../util/Ctx.zig");

pub fn nixShell(_: Ctx, alloc: std.mem.Allocator) []const u8 {
    const in_nix = env.getenv("IN_NIX_SHELL") orelse "";
    return alloc.dupe(u8, in_nix) catch "";
}

pub fn httpProxy(_: Ctx, alloc: std.mem.Allocator) []const u8 {
    if (env.getenv("HTTP_PROXY")) |v| {
        if (v.len > 0) return alloc.dupe(u8, v) catch "";
    }
    const https_proxy = env.getenv("HTTPS_PROXY") orelse "";
    return alloc.dupe(u8, https_proxy) catch "";
}
