const std = @import("std");
pub var DEBUG_MODE = false;

pub fn init() void {
    DEBUG_MODE = std.posix.getenv("STARSHEEP_DEBUG") != null;
}
