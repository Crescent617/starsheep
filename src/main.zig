const std = @import("std");
const yazap = @import("yazap");
const Arg = yazap.Arg;
const starsheep = @import("starsheep");
const shell = starsheep.shell;
const build_info = @import("build_info");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    starsheep.env.setIo(io);

    var app = yazap.App.init(allocator, "starsheep", "A customizable shell prompt generator");
    defer app.deinit();

    var r = app.rootCommand();
    r.setProperty(.help_on_empty_args);

    const shells = &[_][]const u8{"zsh"};

    var prompt = app.createCommand("prompt", "Generate and output the shell prompt");
    try prompt.addArg(Arg.singleValueOption("last-exit-code", null, "The exit code of the last executed command"));
    try prompt.addArg(Arg.singleValueOption("last-duration-ms", null, "The duration in milliseconds of the last executed command"));
    try prompt.addArg(Arg.singleValueOption("jobs", null, "The number of background jobs currently running"));
    try prompt.addArg(Arg.singleValueOptionWithValidValues("shell", null, "The shell type to generate the initialization script for", shells));
    try r.addSubcommand(prompt);

    var init_cmd = app.createCommand("init", "Output shell initialization script");
    try init_cmd.addArg(Arg.positional("shell", "The shell type to generate the initialization script for", null));
    try r.addSubcommand(init_cmd);

    const version_cmd = app.createCommand("version", "Print version information");
    try r.addSubcommand(version_cmd);

    const matches = try app.parseProcess(io, init.minimal.args);

    const stdout = std.Io.File.stdout();

    if (matches.subcommandMatches("prompt")) |am| {
        try promptMain(init, .{
            .shell = am.getSingleValue("shell") orelse "",
            .last_exit_code = am.getSingleValue("last-exit-code"),
            .last_duration_ms = am.getSingleValue("last-duration-ms"),
            .jobs = am.getSingleValue("jobs"),
        });
    } else if (matches.subcommandMatches("init")) |am| {
        const s = am.getSingleValue("shell") orelse return error.MissingArgument;
        if (std.mem.eql(u8, s, "zsh")) {
            try stdout.writeStreamingAll(io, shell.init_zsh_script);
        } else {
            return error.UnsupportedShell;
        }
    } else if (matches.subcommandMatches("version")) |_| {
        try stdout.writeStreamingAll(io, build_info.app_version);
        try stdout.writeStreamingAll(io, "\n");
    } else {
        try app.displayHelp(io);
    }
}

fn promptMain(init: std.process.Init, st: starsheep.ShellState) !void {
    const alloc = init.gpa;
    const io = init.io;

    var app = try starsheep.App.init(alloc);
    defer app.deinit();

    app.shell_state = st;

    const conf_path = try getConfig(init);
    defer alloc.free(conf_path);

    app.applyConfigFile(conf_path) catch |err| {
        std.log.debug("Failed to apply config file '{s}': {}\n", .{ conf_path, err });
    };

    var buf: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buf);
    defer writer.interface.flush() catch {};

    try app.run(&writer.interface);
}

fn getConfig(init: std.process.Init) ![]const u8 {
    const alloc = init.gpa;
    const home_dir = init.environ_map.get("HOME") orelse return error.HomeNotFound;
    return std.Io.Dir.path.join(alloc, &.{ home_dir, ".config", "starsheep.toml" });
}
