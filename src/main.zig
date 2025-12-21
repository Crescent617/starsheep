const std = @import("std");
const starsheep = @import("starsheep");

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var app = try starsheep.App.init(alloc);
    defer app.deinit();

    const conf_path = "starsheep.toml";
    if (statFile(conf_path)) |_| {
        std.log.debug("Loading configuration from: {s}", .{conf_path});

        const conf = try starsheep.Conf.fromTomlFile(alloc, conf_path);
        defer conf.deinit();
        try app.applyConfig(&conf.value);
    }

    var buf: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buf);
    defer writer.interface.flush() catch {};

    try app.run(&writer.interface);
}

fn statFile(path: []const u8) ?std.fs.File.Stat {
    const stat = std.fs.cwd().statFile(path) catch |err| {
        std.log.err("Failed to stat file '{s}': {}", .{ path, err });
        return null;
    };
    return stat;
}
