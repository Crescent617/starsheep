const std = @import("std");
const yazap = @import("yazap");
const Arg = yazap.Arg;
const starsheep = @import("starsheep");
const scripts = @import("scripts/mod.zig");

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();

    const allocator = gpa.allocator();

    var app = yazap.App.init(allocator, "starsheep", "A customizable shell prompt generator");
    defer app.deinit();

    var r = app.rootCommand();
    r.setProperty(.help_on_empty_args);

    var prompt = app.createCommand("prompt", "Generate and output the shell prompt");
    try prompt.addArg(Arg.singleValueOption("last-exit-code", null, "The exit code of the last executed command"));
    try prompt.addArg(Arg.singleValueOption("last-duration-ms", null, "The duration in milliseconds of the last executed command"));
    try prompt.addArg(Arg.singleValueOption("jobs", null, "The number of background jobs currently running"));
    try r.addSubcommand(prompt);

    var init = app.createCommand("init", "Output shell initialization script");
    try init.addArg(Arg.singleValueOptionWithValidValues(
        "shell",
        null,
        "The shell type to generate the initialization script for",
        &[_][]const u8{"zsh"},
    ));
    try r.addSubcommand(init);

    const matches = try app.parseProcess();

    if (matches.subcommandMatches("prompt")) |am| {
        try promptMain(allocator, .{
            .last_exit_code = am.getSingleValue("last-exit-code"),
            .last_duration_ms = am.getSingleValue("last-duration-ms"),
            .jobs = am.getSingleValue("jobs"),
        });
    } else if (matches.subcommandMatches("init")) |am| {
        _ = am.getSingleValue("shell") orelse return error.MissingArgument;
        try std.fs.File.stdout().writeAll(scripts.init_zsh_script);
    } else {
        try app.displayHelp();
    }
}

fn promptMain(alloc: std.mem.Allocator, st: starsheep.ShellState) !void {
    var app = try starsheep.App.init(alloc);
    defer app.deinit();

    app.shell_state = st;

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
