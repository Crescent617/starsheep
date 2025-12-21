const Cmd = @This();
const Self = Cmd;
const Either = @import("util/types.zig").Either;

const std = @import("std");
const fmt = @import("fmt.zig");

name: []const u8,
cmd: Either([]const u8, *const fn (std.mem.Allocator) []const u8),
when: Either([]const u8, *const fn (std.mem.Allocator) bool) = .{ .L = "" },
format: ?[]const u8 = null, // use tmux style format strings, e.g. #[fg=blue,bg=black,bold,underscore]
enabled: bool = true,
timeout_ms: u64 = 500,

pub fn needsEval(self: *const Self, alloc: std.mem.Allocator) !bool {
    if (!self.enabled) {
        return false;
    }
    switch (self.when) {
        .L => |s| {
            if (s.len == 0) {
                return true;
            }
            // execute when_str and check exit code
            var process = std.process.Child.init(&[_][]const u8{ "sh", "-c", s }, alloc);
            const exit_code = try process.spawnAndWait();
            return exit_code.Exited == 0;
        },
        .R => |f| {
            return f(alloc);
        },
    }
}

/// Evaluate the 'when' condition and return any output
pub fn eval(self: *const Self, alloc: std.mem.Allocator) ![]const u8 {
    // std.log.debug("Evaluating command: {s}", .{self.name});
    switch (self.cmd) {
        .L => |cmd_str| {
            const res = try std.process.Child.run(.{
                .argv = &[_][]const u8{ "sh", "-c", cmd_str },
                .allocator = alloc,
            });
            defer alloc.free(res.stderr);
            return res.stdout;
        },
        .R => |cmd_fn| {
            return cmd_fn(alloc);
        },
    }
}

test "Cmd needsEval test" {
    var cmd1 = Cmd{
        .name = "test1",
        .cmd = .{ .L = "" },
        .when = .{ .L = "true" },
        .format = "",
        .enabled = true,
    };
    const res1 = try cmd1.needsEval(std.testing.allocator);
    try std.testing.expect(res1 == true);

    var cmd2 = Cmd{
        .name = "test2",
        .cmd = .{ .L = "" },
        .when = .{ .L = "false" },
        .format = "",
        .enabled = true,
    };
    const res = try cmd2.needsEval(std.testing.allocator);
    try std.testing.expect(res == false);
}

fn func_when_true(_: std.mem.Allocator) bool {
    return true;
}

fn func_when_false(_: std.mem.Allocator) bool {
    return false;
}

test "Cmd needsEval with function test" {
    var cmd = Cmd{
        .name = "test_func",
        .cmd = .{ .L = "" },
        .when = .{ .R = func_when_true },
        .format = "",
        .enabled = true,
    };
    const res = try cmd.needsEval(std.testing.allocator);
    try std.testing.expect(res == true);

    cmd.when = .{ .R = func_when_false };
    const res2 = try cmd.needsEval(std.testing.allocator);
    try std.testing.expect(res2 == false);
}

test "Cmd eval test" {
    var cmd = Cmd{
        .name = "echo_test",
        .cmd = .{ .L = "echo Hello, World!" },
        .when = .{ .L = "true" },
        .format = "",
        .enabled = true,
    };
    const output = try cmd.eval(std.testing.allocator);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings(output, "Hello, World!\n");
}

fn func_cmd(_: std.mem.Allocator) []const u8 {
    return "Function Output\n";
}

test "Cmd eval with function test" {
    var cmd = Cmd{
        .name = "func_cmd_test",
        .cmd = .{ .R = func_cmd },
        .when = .{ .L = "true" },
        .format = "",
        .enabled = true,
    };
    const output = try cmd.eval(std.testing.allocator);
    try std.testing.expectEqualStrings(output, "Function Output\n");
}
