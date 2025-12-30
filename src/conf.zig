const std = @import("std");
const toml = @import("toml");

pub const AppConf = struct {
    prompt_hint: []const u8 = "󱙝 ",
    cmds: []CmdConf = &[_]CmdConf{},

    pub fn fromToml(
        allocator: std.mem.Allocator,
        toml_str: []const u8,
    ) !toml.Parsed(AppConf) {
        var parser = toml.Parser(AppConf).init(allocator);
        defer parser.deinit();
        const result = try parser.parseString(toml_str);
        return result;
    }

    pub fn fromTomlFile(allocator: std.mem.Allocator, path: []const u8) !toml.Parsed(AppConf) {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 100 * 1024); // max 100KB
        defer allocator.free(content);

        return try AppConf.fromToml(allocator, content);
    }
};

pub const CmdConf = struct {
    name: []const u8, // unique name for the command
    cmd: []const u8,
    when: ?[]const u8,
    format: ?[]const u8, // use tmux-format style e.g. "#[fg=black,bg=white,bold]"
    enabled: ?bool = true, // default to true

};

test "AppConf toml unmarshal example" {
    const s =
        \\ [[cmds]]
        \\ name = "greet"
        \\ cmd = "echo 'Hello, World!'"
        \\ format = "#[fg=green,bold]"
        \\
        \\ [[cmds]]
        \\ name = "list"
        \\ cmd = "ls -la"
        \\ when = "true"
        \\ format = "#[fg=blue]"
        \\ enabled = false
    ;

    const app_conf_res = try AppConf.fromToml(std.testing.allocator, s);
    defer app_conf_res.deinit();
    const app_conf = app_conf_res.value;

    const cmd1 = app_conf.cmds[0];
    try std.testing.expectEqualStrings("greet", cmd1.name);
    try std.testing.expectEqualStrings("echo 'Hello, World!'", cmd1.cmd);
    try std.testing.expectEqualStrings("#[fg=green,bold]", cmd1.format orelse "");
    try std.testing.expectEqual(cmd1.enabled orelse true, true);

    const cmd2 = app_conf.cmds[1];
    try std.testing.expectEqualStrings("list", cmd2.name);
    try std.testing.expectEqualStrings("ls -la", cmd2.cmd);
    try std.testing.expectEqualStrings("true", cmd2.when orelse "");
    try std.testing.expectEqualStrings("#[fg=blue]", cmd2.format orelse "");
    try std.testing.expectEqual(cmd2.enabled orelse true, false);
}
