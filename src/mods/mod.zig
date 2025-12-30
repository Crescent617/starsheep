const std = @import("std");
const dir = @import("dir.zig");
const git = @import("git.zig");
const Cmd = @import("../Cmd.zig");
const util = @import("util.zig");

pub const builtins = [_]Cmd{ .{
    .name = "user",
    .cmd = .{ .R = username },
    .format = "#[fg=yellow,bold]$output @",
}, .{
    .name = "host",
    .cmd = .{ .R = hostname },
    .format = "#[fg=green,bold]󰢹 $output",
}, .{
    .name = "cwd",
    .cmd = .{ .R = dir.curDir },
    .format = "#[fg=cyan,bold]$output",
}, .{
    .name = "git_branch",
    .cmd = .{ .R = git.gitBranch },
    .format = "#[fg=magenta,bold] $output",
}, .{
    .name = "git_state",
    .cmd = .{ .R = git.gitState },
    .format = "#[fg=yellow,bold]$output",
}, .{
    .name = "git_status",
    .cmd = .{ .R = git.gitStatus },
    .format = "#[fg=red,bold][$output]",
}, .{
    .name = "python",
    .cmd = .{ .R = pyVer },
    .when = .{ .L = "" },
    .format = "#[fg=yellow,bold] $output",
}, .{
    .name = "zig",
    .cmd = .{ .R = zigVer },
    .format = "#[fg=yellow,bold] $output",
}, .{
    .name = "nix-shell",
    .cmd = .{ .R = nixShell },
    .format = "#[fg=cyan,bold] $output",
}, .{
    .name = "go",
    .cmd = .{ .R = goVer },
    .format = "#[fg=cyan,bold]🐹$output",
}, .{
    .name = "rust",
    .cmd = .{ .R = rustVer },
    .format = "#[fg=red,bold]🦀$output",
}, .{
    .name = "node",
    .cmd = .{ .R = nodeVer },
    .format = "#[fg=green,bold] $output",
}, .{
    .name = "http_proxy",
    .cmd = .{ .R = httpProxy },
    .format = "#[fg=blue,bold] $output",
} };

fn zigVer(alloc: std.mem.Allocator) []const u8 {
    if (!util.existsFileUpwards(alloc, ".", "build.zig")) {
        return "";
    }
    const builtin = @import("builtin");
    return alloc.dupe(u8, builtin.zig_version_string) catch return "";
}

fn pyVer(alloc: std.mem.Allocator) []const u8 {
    const ev = "VIRTUAL_ENV_PROMPT";
    const venv = std.posix.getenv(ev) orelse return "";

    if (util.findFileUpwards(alloc, ".", ".python-version")) |p| {
        defer p.deinit(alloc);
        const ver = std.fs.cwd().readFileAlloc(alloc, p.path, 256) catch "";
        if (ver.len > 0) {
            return ver;
        }
    }

    // Only get major.minor version for faster execution
    const ver = util.runSubprocess(alloc, &[_][]const u8{ "python3", "-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}', end='')" }) catch return "";
    defer alloc.free(ver);

    return std.fmt.allocPrint(alloc, "{s}({s})", .{ ver, std.fs.path.basename(venv) }) catch return "";
}

fn nixShell(alloc: std.mem.Allocator) []const u8 {
    const ev = "IN_NIX_SHELL";
    const in_nix = std.process.getEnvVarOwned(alloc, ev) catch "";
    return in_nix;
}

fn goVer(alloc: std.mem.Allocator) []const u8 {
    const exists = util.existsFileUpwards(alloc, ".", "go.mod");
    if (!exists) {
        return "";
    }

    const ver = util.runSubprocess(alloc, &[_][]const u8{ "go", "version" }) catch return "";
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

fn rustVer(alloc: std.mem.Allocator) []const u8 {
    const exists = util.existsFileUpwards(alloc, ".", "Cargo.toml");
    if (!exists) return "";

    // 1. 尝试直接获取 rustup 链下的真实 rustc 路径 (跳过 shim)
    const fast_ver = getRustupDirectVersion(alloc) catch null;
    if (fast_ver) |v| return v;

    std.log.debug("Failed to get rustc version via rustup direct method: {any}", .{fast_ver});

    // 2. 兜底方案：直接运行系统路径下的 rustc
    const ver = util.runSubprocess(alloc, &[_][]const u8{ "rustc", "--version" }) catch return "";
    defer alloc.free(ver);

    var iter = std.mem.tokenizeScalar(u8, ver, ' ');
    _ = iter.next(); // "rustc"
    if (iter.next()) |version_part| {
        return alloc.dupe(u8, version_part) catch "";
    }
    return "";
}

/// 尝试跳过 rustup shim，直接找到真实工具链二进制
fn getRustupDirectVersion(alloc: std.mem.Allocator) ![]const u8 {
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
    const ver = try util.runSubprocess(alloc, &[_][]const u8{ real_rustc_path, "--version" });
    defer alloc.free(ver);

    var iter = std.mem.tokenizeScalar(u8, ver, ' ');
    _ = iter.next();
    if (iter.next()) |v| return try alloc.dupe(u8, v);
    return error.ParseError;
}

fn nodeVer(alloc: std.mem.Allocator) []const u8 {
    const exists = util.existsFileUpwards(alloc, ".", "package.json");
    if (!exists) {
        return "";
    }

    const ver = util.runSubprocess(alloc, &[_][]const u8{ "node", "--version" }) catch return "";
    defer alloc.free(ver);

    // 输出类似 "v14.17.0"
    return alloc.dupe(u8, ver[1..]) catch return "";
}

fn username(alloc: std.mem.Allocator) []const u8 {
    if (!std.process.hasEnvVarConstant("SSH_CONNECTION")) {
        return "";
    }
    return std.process.getEnvVarOwned(alloc, "USER") catch "";
}

fn hostname(alloc: std.mem.Allocator) []const u8 {
    if (!std.process.hasEnvVarConstant("SSH_CONNECTION")) {
        return "";
    }
    var buf: [std.c.HOST_NAME_MAX]u8 = undefined;
    // std.posix.gethostname 在各平台通用
    const name = std.posix.gethostname(&buf) catch "";
    return alloc.dupe(u8, name) catch "";
}

fn httpProxy(alloc: std.mem.Allocator) []const u8 {
    const http_proxy = std.process.getEnvVarOwned(alloc, "HTTP_PROXY") catch "";
    if (http_proxy.len == 0) {
        const https_proxy = std.process.getEnvVarOwned(alloc, "HTTPS_PROXY") catch "";
        return https_proxy;
    }
    return http_proxy;
}
