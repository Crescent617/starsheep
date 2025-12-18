const std = @import("std");
const Cmd = @import("starsheep").Cmd;

const template: Cmd = .{
    .when = .{ .L = "" },
};

pub const builtins = [_]Cmd{
    Cmd{
        .name = "git_status",
        .when = template.when,
    },
};
