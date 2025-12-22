//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const Cmd = @import("Cmd.zig");
pub const Conf = @import("conf.zig").AppConf;
const builtins = @import("builtin/mod.zig").builtins;
const chameleon = @import("chameleon");
const fmt = @import("fmt.zig");
const toml = @import("toml");
pub const shell = @import("shell/mod.zig");

// Import cleanup functions
const cleanupVersionCache = @import("builtin/mod.zig").cleanupVersionCache;
const git = @import("builtin/git.zig");

pub const ShellState = struct {
    shell: []const u8 = "zsh",
    last_exit_code: ?[]const u8 = null,
    last_duration_ms: ?[]const u8 = null,
    jobs: ?[]const u8 = null,

    fn lastDurationMs(self: *ShellState, alloc: std.mem.Allocator) ![]const u8 {
        if (self.last_duration_ms == null) {
            return "";
        }
        const dur_str = self.last_duration_ms.?;
        const dur_f = std.fmt.parseFloat(f64, dur_str) catch return "0";
        var dur_ms: u32 = @intFromFloat(dur_f);

        var arr: std.ArrayList(u8) = .empty;
        defer arr.deinit(alloc);

        const DAY = 1000 * 60 * 60 * 24;
        const HOUR = 1000 * 60 * 60;
        const MIN = 1000 * 60;
        const SEC = 1000;

        if (dur_ms >= DAY) {
            const days = dur_ms / DAY;
            try arr.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{d}d", .{days}));
            dur_ms = dur_ms % DAY;
        }
        if (dur_ms >= HOUR) {
            const hours = dur_ms / HOUR;
            try arr.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{d}h", .{hours}));
            dur_ms = dur_ms % HOUR;
        }
        if (dur_ms >= MIN) {
            const mins = dur_ms / MIN;
            try arr.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{d}m", .{mins}));
            dur_ms = dur_ms % MIN;
        }
        if (dur_ms >= SEC) {
            const secs = dur_ms / SEC;
            try arr.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{d}s", .{secs}));
            dur_ms = dur_ms % SEC;
        }
        // only show ms if duration > 100ms and no other units
        if (dur_ms > 100 and arr.items.len == 0) {
            try arr.appendSlice(alloc, try std.fmt.allocPrint(alloc, "{d}ms", .{dur_ms}));
        }
        return try arr.toOwnedSlice(alloc);
    }
};

pub const App = struct {
    cmds: std.ArrayList(Cmd),
    alloc: std.mem.Allocator,
    formatter: chameleon.RuntimeChameleon,
    parsed_conf: ?toml.Parsed(Conf) = null,
    shell_state: ShellState = .{},

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !App {
        var arr = std.ArrayList(Cmd).empty;
        try arr.appendSlice(alloc, &builtins);

        const app = App{
            .cmds = arr,
            .alloc = alloc,
            .formatter = chameleon.initRuntime(.{
                .allocator = alloc,
            }),
        };
        return app;
    }

    pub fn deinit(self: *App) void {
        // Cleanup caches
        cleanupVersionCache(self.alloc);
        git.deinit();

        self.cmds.deinit(self.alloc);
        self.formatter.deinit();
        if (self.parsed_conf) |conf| {
            conf.deinit();
        }
    }

    pub fn applyConfigFile(self: *App, path: []const u8) !void {
        const conf = try Conf.fromTomlFile(self.alloc, path);
        self.parsed_conf = conf;
        try self.applyConfig(&conf.value);
    }

    pub fn applyConfig(self: *App, cfg: *const Conf) !void {
        var cmd_map = std.StringHashMap(*Cmd).init(self.alloc);
        defer cmd_map.deinit();

        // 方法2: 使用指针算术
        for (self.cmds.items, 0..) |_, i| {
            _ = try cmd_map.put(self.cmds.items[i].name, &self.cmds.items[i]);
        }

        for (cfg.cmds) |cmd_conf| {
            if (cmd_map.get(cmd_conf.name)) |existing_cmd| {
                existing_cmd.enabled = cmd_conf.enabled orelse existing_cmd.enabled;
                existing_cmd.format = cmd_conf.format orelse existing_cmd.format;
            } else if (cmd_conf.enabled orelse true) {
                const cmd = Cmd{
                    .name = cmd_conf.name,
                    .cmd = .{ .L = cmd_conf.cmd },
                    .when = .{ .L = cmd_conf.when orelse "" },
                    .format = cmd_conf.format,
                    .enabled = cmd_conf.enabled orelse true,
                };
                try self.cmds.append(self.alloc, cmd);
            }
        }
    }

    pub fn run(self: *App, out: *std.io.Writer) !void {
        var buf = std.io.Writer.Allocating.init(self.alloc);
        defer buf.deinit();

        var writer = &buf.writer;

        _ = try writer.writeByte('\n');

        // Run commands in parallel for better performance
        const results = try self.alloc.alloc([]const u8, self.cmds.items.len);
        defer {
            for (results) |res| {
                if (res.len > 0) self.alloc.free(res);
            }
            self.alloc.free(results);
        }

        const needs_eval = try self.alloc.alloc(bool, self.cmds.items.len);
        defer self.alloc.free(needs_eval);

        // First pass: check which commands need evaluation
        for (self.cmds.items, 0..) |cmd, i| {
            needs_eval[i] = try cmd.needsEval(self.alloc);
            results[i] = "";
        }

        // Second pass: evaluate commands that are needed
        for (self.cmds.items, needs_eval, 0..) |cmd, should_eval, i| {
            if (!should_eval) continue;
            results[i] = try cmd.eval(self.alloc);
        }

        // Third pass: format and write results
        for (self.cmds.items, results, needs_eval) |cmd, res, should_eval| {
            if (!should_eval or res.len == 0) continue;

            try fmt.format(self.alloc, cmd.format, res, &self.formatter, writer);
            _ = try writer.writeByte(' ');
        }

        const lastDur = try self.shell_state.lastDurationMs(self.alloc);
        if (lastDur.len != 0) {
            try self.formatter.gray().print(writer, "⏱ {s}", .{lastDur});
        }

        _ = try writer.writeByte('\n');

        if (self.shell_state.jobs) |jobs| {
            if (!std.mem.eql(u8, jobs, "0"))
                try self.formatter.blue().print(writer, " {s} ", .{jobs});
        }

        const prompt_symbol = "󱙝";

        if (self.shell_state.last_exit_code) |code| {
            if (std.mem.eql(u8, code, "0")) {
                try self.formatter.green().print(writer, "{s}", .{prompt_symbol});
            } else if (std.mem.eql(u8, code, "1")) {
                try self.formatter.red().print(writer, "{s}", .{prompt_symbol});
            } else {
                try self.formatter.red().print(writer, "[{s}]{s}", .{ code, prompt_symbol });
            }
        } else {
            try self.formatter.green().print(writer, "{s}", .{prompt_symbol});
        }

        const buf_slice = try buf.toOwnedSlice();
        defer self.alloc.free(buf_slice);

        // post process and write to out
        if (std.mem.eql(u8, self.shell_state.shell, "zsh")) {
            const final_str = try shell.wrapAnsiForZsh(self.alloc, buf_slice);
            defer self.alloc.free(final_str);
            try out.writeAll(final_str);
        } else {
            try out.writeAll(buf_slice);
        }
    }
};

test {
    // 这行代码会让 Zig 递归地去检查并运行上面所有被引用(public)容器里的测试
    std.testing.refAllDecls(@This());
}
