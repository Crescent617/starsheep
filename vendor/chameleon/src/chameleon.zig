const std = @import("std");
pub const ComptimeChameleon = @import("api/Comptime.zig");
pub const RuntimeChameleon = @import("api/Runtime.zig");
pub const HexColors = @import("colors.zig");

pub fn initComptime() ComptimeChameleon {
    return .{};
}

const Config = struct {
    allocator: std.mem.Allocator,
    detect_no_color: bool = true,
};

pub fn initRuntime(config: Config) RuntimeChameleon {
    return .{
        .allocator = config.allocator,
        // VENDORED FIX for zig 0.16: std.process.hasEnvVarConstant was removed
        // (env vars are no longer global). Use libc getenv instead; starsheep
        // always links libc. Revert to upstream once tr1ckydev/chameleon supports 0.16.
        .no_color = if (!config.detect_no_color) false else std.c.getenv("NO_COLOR") != null,
    };
}

test {
    std.testing.refAllDecls(@This());
}
