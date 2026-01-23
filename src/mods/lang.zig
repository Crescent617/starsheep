const std = @import("std");
const util = @import("util.zig");
const Ctx = @import("../util/Ctx.zig");
const run = @import("../util/process.zig").run;

pub fn zigVer(ctx: Ctx, alloc: std.mem.Allocator) []const u8 {
    _ = ctx;
    if (!util.existsFileUpwards(alloc, ".", "build.zig")) {
        return "";
    }
    const builtin = @import("builtin");
    return alloc.dupe(u8, builtin.zig_version_string) catch return "";
}

pub fn pyVer(ctx: Ctx, alloc: std.mem.Allocator) []const u8 {
    const ev = "VIRTUAL_ENV_PROMPT";
    const venv = std.posix.getenv(ev) orelse return "";

    var ver: []const u8 = "";

    if (util.findFileUpwards(alloc, ".", ".python-version")) |p| {
        defer p.deinit(alloc);
        ver = std.fs.cwd().readFileAlloc(alloc, p.path, 256) catch "";
    } else {
    const ver_res = run(.{ .ctx = ctx, .allocator = alloc, .argv = &[_][]const u8{ "python3", "-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}', end='')" } }) catch return "";
        ver = ver_res.stdout;
    }

    defer alloc.free(ver);

    const trimmed_venv = std.mem.trim(u8, venv, "()\n\r\t ");
    const trimmed_ver = std.mem.trim(u8, ver, "\n\r\t ");
    return std.fmt.allocPrint(alloc, "{s}({s})", .{ trimmed_ver, trimmed_venv }) catch return "";
}

pub fn goVer(ctx: Ctx, alloc: std.mem.Allocator) []const u8 {
    const exists = util.existsFileUpwards(alloc, ".", "go.mod");
    if (!exists) {
        return "";
    }

    const ver_res = run(.{ .ctx = ctx, .allocator = alloc, .argv = &[_][]const u8{ "go", "version" } }) catch return "";
    const ver = ver_res.stdout;
    defer alloc.free(ver);

    // 输出类似 "go version go1.16.3 linux/amd64"
    var iter = std.mem.tokenizeScalar(u8, ver, ' ');
    _ = iter.next(); // "go"
    _ = iter.next(); // "version"
    if (iter.next()) |version_part| {
        return alloc.dupe(u8, version_part[2..]) catch return "";
    }
    return "";
}

pub fn rustVer(ctx: Ctx, alloc: std.mem.Allocator) []const u8 {
    const exists = util.existsFileUpwards(alloc, ".", "Cargo.toml");
    if (!exists) return "";

    // 1. 尝试直接获取 rustup 链下的真实 rustc 路径 (跳过 shim)
    const fast_ver = getRustupDirectVersion(ctx, alloc) catch null;
    if (fast_ver) |v| return v;

    std.log.debug("Failed to get rustc version via rustup direct method: {any}", .{fast_ver});

    // 2. 兜底方案：直接运行系统路径下的 rustc
    const ver_res = run(.{ .ctx = ctx, .allocator = alloc, .argv = &[_][]const u8{ "rustc", "--version" } }) catch return "";
    const ver = ver_res.stdout;
    defer alloc.free(ver);

    var iter = std.mem.tokenizeScalar(u8, ver, ' ');
    _ = iter.next(); // "rustc"
    if (iter.next()) |version_part| {
        return alloc.dupe(u8, version_part) catch "";
    }
    return "";
}

/// 尝试跳过 rustup shim，直接找到真实工具链二进制
fn getRustupDirectVersion(ctx: Ctx, alloc: std.mem.Allocator) ![]const u8 {
    const home = std.process.getEnvVarOwned(alloc, "HOME") catch return error.NoHome;
    defer alloc.free(home);

    // 读取 ~/.rustup/settings.toml
    const settings_path = try std.fs.path.join(alloc, &[_][]const u8{ home, ".rustup", "settings.toml" });
    defer alloc.free(settings_path);

    const content = std.fs.cwd().readFileAlloc(alloc, settings_path, 8192) catch return error.NoSettings;
    defer alloc.free(content);

    var default_toolchain: ?[]const u8 = null;
    var lines = std.mem.tokenizeScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "default_toolchain")) |_| {
            var it = std.mem.tokenizeAny(u8, line, " =\"");
            _ = it.next(); // skip default_toolchain
            if (it.next()) |val| {
                default_toolchain = try alloc.dupe(u8, val);
                break;
            }
        }
    }
    const tc = default_toolchain orelse return error.NoDefaultTC;
    defer alloc.free(tc);

    // 构建真实路径: ~/.rustup/toolchains/STABLE_NAME/bin/rustc
    const real_rustc_path = try std.fs.path.join(alloc, &[_][]const u8{ home, ".rustup", "toolchains", tc, "bin", "rustc" });
    defer alloc.free(real_rustc_path);

    // 使用绝对路径运行（不经过 PATH 搜索，不经过 shim）
    const ver_res = try run(.{ .ctx = ctx, .allocator = alloc, .argv = &[_][]const u8{ real_rustc_path, "--version" } });
    const ver = ver_res.stdout;
    defer alloc.free(ver);

    var iter = std.mem.tokenizeScalar(u8, ver, ' ');
    _ = iter.next();
    if (iter.next()) |v| return try alloc.dupe(u8, v);
    return error.ParseError;
}

pub fn nodeVer(ctx: Ctx, alloc: std.mem.Allocator) []const u8 {
    const exists = util.existsFileUpwards(alloc, ".", "package.json");
    if (!exists) {
        return "";
    }

    const ver_res = run(.{ .ctx = ctx, .allocator = alloc, .argv = &[_][]const u8{ "node", "--version" } }) catch return "";
    const ver = ver_res.stdout;
    defer alloc.free(ver);

    // 输出类似 "v14.17.0"
    return alloc.dupe(u8, ver[1..]) catch return "";
}
