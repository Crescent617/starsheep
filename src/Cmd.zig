const Cmd = @This();
const Self = Cmd;
const std = @import("std");

name: []const u8,
cmd: []const u8,
cmd_fn: ?*const fn () []const u8 = null,
when: ?[]const u8,
when_fn: ?*const fn () bool = null,
format: []const u8,
enabled: bool = true,

pub fn needsEval(self: *const Self, alloc: std.mem.Allocator) !bool {
    if (self.when_fn) |when_fn| {
        return when_fn();
    }
    if (self.when) |when_str| {
        // execute when_str and check exit code
        var process = std.process.Child.init(&[_][]const u8{ "sh", "-c", when_str }, alloc);
        const exit_code = try process.spawnAndWait();
        return exit_code.Exited == 0;
    }
    return true;
}

/// Evaluate the 'when' condition and return any output
pub fn eval(self: *const Self, alloc: std.mem.Allocator) ![]const u8 {
    if (self.cmd_fn) |cmd_fn| {
        return cmd_fn();
    }
    var p = std.process.Child.init(&[_][]const u8{ "sh", "-c", self.cmd }, alloc);
    p.stdin_behavior = .Ignore;
    p.stdout_behavior = .Pipe;
    p.stderr_behavior = .Pipe;

    _ = try p.spawn();
    defer _ = p.kill() catch |err| {
        std.log.err("Failed to kill process: {}\n", .{err});
    };

    if (p.stdout) |stdout_pipe| {
        return try stdout_pipe.readToEndAlloc(alloc, 4096); // max 4KB output
    } else {
        return "";
    }
}

test "Cmd needsEval test" {
    var cmd1 = Cmd{
        .name = "test1",
        .cmd = "",
        .when_fn = null,
        .when = "true",
        .format = "",
        .enabled = true,
    };
    const res1 = try cmd1.needsEval(std.testing.allocator);
    try std.testing.expect(res1 == true);

    var cmd2 = Cmd{
        .name = "test2",
        .cmd = "",
        .when_fn = null,
        .when = "false",
        .format = "",
        .enabled = true,
    };
    const res = try cmd2.needsEval(std.testing.allocator);
    try std.testing.expect(res == false);
}

fn func_when_true() bool {
    return true;
}

fn func_when_false() bool {
    return false;
}

test "Cmd needsEval with function test" {
    var cmd = Cmd{
        .name = "test_func",
        .cmd = "",
        .when_fn = func_when_true,
        .when = null,
        .format = "",
        .enabled = true,
    };
    const res = try cmd.needsEval(std.testing.allocator);
    try std.testing.expect(res == true);

    cmd.when_fn = func_when_false;
    const res2 = try cmd.needsEval(std.testing.allocator);
    try std.testing.expect(res2 == false);
}

test "Cmd eval test" {
    var cmd = Cmd{
        .name = "echo_test",
        .cmd = "echo Hello, World!",
        .when_fn = null,
        .when = null,
        .format = "",
        .enabled = true,
    };
    const output = try cmd.eval(std.testing.allocator);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings(output, "Hello, World!\n");
}

fn func_cmd() []const u8 {
    return "Function Output\n";
}

test "Cmd eval with function test" {
    var cmd = Cmd{
        .name = "func_cmd_test",
        .cmd = "",
        .cmd_fn = func_cmd,
        .when_fn = null,
        .when = null,
        .format = "",
        .enabled = true,
    };
    const output = try cmd.eval(std.testing.allocator);
    try std.testing.expectEqualStrings(output, "Function Output\n");
}
