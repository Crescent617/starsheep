const std = @import("std");
const dir = @import("dir.zig");
const git = @import("git.zig");
const Cmd = @import("../Cmd.zig");

pub const builtins = [_]Cmd{
    Cmd{
        .name = "cwd",
        .when = .{ .L = "" },
        .cmd = .{ .R = dir.curDir },
        .format = "#[fg=cyan,bold]$output",
    },
    Cmd{
        .name = "git_branch",
        .when = .{ .L = "" },
        .cmd = .{ .R = git.gitBranch },
        .format = "#[fg=magenta,bold] $output",
    },
    Cmd{
        .name = "git_status",
        .when = .{ .L = "" },
        .cmd = .{ .R = git.gitStatus },
        .format = "#[fg=red,bold]$output",
    },
};
