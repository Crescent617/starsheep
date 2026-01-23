const std = @import("std");
const Ctx = @import("../util/Ctx.zig");

pub fn nixShell(_: Ctx, alloc: std.mem.Allocator) []const u8 {
    const ev = "IN_NIX_SHELL";
    const in_nix = std.process.getEnvVarOwned(alloc, ev) catch "";
    return in_nix;
}

pub fn httpProxy(_: Ctx, alloc: std.mem.Allocator) []const u8 {
    const http_proxy = std.process.getEnvVarOwned(alloc, "HTTP_PROXY") catch "";
    if (http_proxy.len == 0) {
        const https_proxy = std.process.getEnvVarOwned(alloc, "HTTPS_PROXY") catch "";
        return https_proxy;
    }
    return http_proxy;
}
