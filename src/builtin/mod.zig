const std = @import("std");
const dir = @import("dir.zig");
const git = @import("git.zig");
const Cmd = @import("../Cmd.zig");
const util = @import("util.zig");

// Cache for version detection to avoid repeated subprocess calls
const VersionCache = struct {
    python: ?[]const u8 = null,
    zig: ?[]const u8 = null,
    go: ?[]const u8 = null,
    rust: ?[]const u8 = null,
    node: ?[]const u8 = null,

    fn deinit(self: *VersionCache, alloc: std.mem.Allocator) void {
        if (self.python) |v| alloc.free(v);
        if (self.zig) |v| alloc.free(v);
        if (self.go) |v| alloc.free(v);
        if (self.rust) |v| alloc.free(v);
        if (self.node) |v| alloc.free(v);
        self.* = .{};
    }
};

var version_cache: ?VersionCache = null;
var version_cache_initialized = false;

fn getVersionCache() *VersionCache {
    if (!version_cache_initialized) {
        version_cache = VersionCache{};
        version_cache_initialized = true;
    }
    return &version_cache.?;
}

pub fn cleanupVersionCache(alloc: std.mem.Allocator) void {
    if (version_cache) |*cache| {
        cache.deinit(alloc);
        version_cache = null;
        version_cache_initialized = false;
    }
}

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

fn zigVer(alloc: std.mem.Allocator) []const u8 {
    if (!util.existsFileUpwards(alloc, ".", "build.zig")) {
        return "";
    }
    const builtin = @import("builtin");
    return alloc.dupe(u8, builtin.zig_version_string) catch return "";
}

fn pyVer(alloc: std.mem.Allocator) []const u8 {
    const cache = getVersionCache();

    // Check cache first
    if (cache.python) |cached| {
        return alloc.dupe(u8, cached) catch return "";
    }

    const ev = "VIRTUAL_ENV_PROMPT";
    const venv = std.process.getEnvVarOwned(alloc, ev) catch "";
    if (venv.len == 0) {
        return "";
    }
    defer alloc.free(venv);

    // Only get major.minor version for faster execution
    const ver = util.runSubprocess(alloc, &[_][]const u8{ "python3", "-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}', end='')" }) catch return "";
    defer alloc.free(ver);

    const result = std.fmt.allocPrint(alloc, "{s}({s})", .{ ver, std.fs.path.basename(venv) }) catch return "";
    cache.python = alloc.dupe(u8, result) catch return "";
    return result;
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
    const cache = getVersionCache();

    // Check cache first
    if (cache.go) |cached| {
        return alloc.dupe(u8, cached) catch return "";
    }

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
        const result = alloc.dupe(u8, version_part[2..]) catch return "";
        cache.go = alloc.dupe(u8, result) catch return "";
        return result;
    }
    return "";
}

fn rustVer(alloc: std.mem.Allocator) []const u8 {
    const cache = getVersionCache();

    // Check cache first
    if (cache.rust) |cached| {
        return alloc.dupe(u8, cached) catch return "";
    }

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
        const result = alloc.dupe(u8, version_part) catch return "";
        cache.rust = alloc.dupe(u8, result) catch return "";
        return result;
    }
    return "";
}

fn nodeVer(alloc: std.mem.Allocator) []const u8 {
    const cache = getVersionCache();

    // Check cache first
    if (cache.node) |cached| {
        return alloc.dupe(u8, cached) catch return "";
    }

    const exists = util.existsFileUpwards(alloc, ".", "package.json");
    if (!exists) {
        return "";
    }

    const ver = util.runSubprocess(alloc, &[_][]const u8{ "node", "--version" }) catch return "";
    defer alloc.free(ver);

    // 输出类似 "v14.17.0"
    const result = alloc.dupe(u8, ver[1..]) catch return "";
    cache.node = alloc.dupe(u8, result) catch return "";
    return result;
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
