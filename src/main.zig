const std = @import("std");
const starsheep = @import("starsheep");

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();

    const alloc = gpa.allocator();

    var app = try starsheep.App.init(alloc);
    defer app.deinit();

    const conf_path = try getConfig(alloc);
    defer alloc.free(conf_path);

    app.applyConfigFile(conf_path) catch |err| {
        std.log.debug("Failed to apply config file '{s}': {}\n", .{ conf_path, err });
    };

    var buf: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buf);
    defer writer.interface.flush() catch {};

    try app.run(&writer.interface);
}

fn getConfig(alloc: std.mem.Allocator) ![]const u8 {
    const home_dir = try std.process.getEnvVarOwned(alloc, "HOME");
    defer alloc.free(home_dir);
    return std.fs.path.join(alloc, &.{ home_dir, ".config", "starsheep.toml" });
}
