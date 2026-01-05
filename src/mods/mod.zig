const git = @import("git.zig");
const dir = @import("dir.zig");
const lang = @import("lang.zig");
const host = @import("host.zig");
const env = @import("env.zig");
const Cmd = @import("../Cmd.zig");

pub const builtins = [_]Cmd{ .{
    .name = "user",
    .cmd = .{ .R = host.username },
    .format = "#[fg=yellow,bold]$output @",
}, .{
    .name = "host",
    .cmd = .{ .R = host.hostname },
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
    .cmd = .{ .R = lang.pyVer },
    .when = .{ .L = "" },
    .format = "#[fg=yellow,bold] $output",
}, .{
    .name = "zig",
    .cmd = .{ .R = lang.zigVer },
    .format = "#[fg=yellow,bold] $output",
}, .{
    .name = "nix-shell",
    .cmd = .{ .R = env.nixShell },
    .format = "#[fg=cyan,bold] $output",
}, .{
    .name = "go",
    .cmd = .{ .R = lang.goVer },
    .format = "#[fg=cyan,bold]🐹$output",
}, .{
    .name = "rust",
    .cmd = .{ .R = lang.rustVer },
    .format = "#[fg=red,bold]🦀$output",
}, .{
    .name = "node",
    .cmd = .{ .R = lang.nodeVer },
    .format = "#[fg=green,bold] $output",
}, .{
    .name = "http_proxy",
    .cmd = .{ .R = env.httpProxy },
    .format = "#[fg=blue,bold] $output",
} };
