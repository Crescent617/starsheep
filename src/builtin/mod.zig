const std = @import("std");
const Cmd = @import("starsheep").Cmd;

pub const builtins = [_]Cmd{
    Cmd{
        .name = "git_status",
    },
};
