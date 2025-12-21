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
    .name = "git_status",
    .cmd = .{ .R = git.gitStatus },
    .format = "#[fg=red,bold]$output",
}, .{
    .name = "python",
    .cmd = .{ .R = pyVer },
    .when = .{ .L = "" },
    .format = "#[fg=yellow,bold]🐍$output",
}, .{
    .name = "zig",
    .cmd = .{ .R = zigVer },
    .format = "#[fg=green,bold]🦎$output",
}, .{
    .name = "nix-shell",
    .cmd = .{ .R = nixShell },
    .format = "#[fg=cyan,bold]❄️$output",
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

fn zigVer(_: std.mem.Allocator) []const u8 {
    const builtin = @import("builtin");
    return builtin.zig_version_string;
}

fn pyVer(alloc: std.mem.Allocator) []const u8 {
    const ev = "VIRTUAL_ENV_PROMPT";
    const venv = std.process.getEnvVarOwned(alloc, ev) catch "";
    if (venv.len == 0) {
        return "";
    }
    defer alloc.free(venv);

    const ver = util.runSubprocess(alloc, &[_][]const u8{ "python3", "-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}', end='')" }) catch return "";
    defer alloc.free(ver);

    return std.fmt.allocPrint(alloc, "{s}({s})", .{ ver, venv }) catch return "";
}

fn nixShell(alloc: std.mem.Allocator) []const u8 {
    const ev = "IN_NIX_SHELL";
    const in_nix = std.process.getEnvVarOwned(alloc, ev) catch "";
    if (in_nix.len == 0) {
        return "";
    }
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
    if (!exists) {
        return "";
    }

    const ver = util.runSubprocess(alloc, &[_][]const u8{ "rustc", "--version" }) catch return "";
    defer alloc.free(ver);

    // 输出类似 "rustc 1.52.1 (9bc8c42bb 2021-05-09)"
    var iter = std.mem.tokenizeScalar(u8, ver, ' ');
    _ = iter.next(); // "rustc"
    if (iter.next()) |version_part| {
        return alloc.dupe(u8, version_part) catch return "";
    }
    return "";
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
    var buf: [std.os.linux.HOST_NAME_MAX]u8 = undefined;
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
