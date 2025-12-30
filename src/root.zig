//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const Cmd = @import("Cmd.zig");
pub const Conf = @import("conf.zig").AppConf;
const builtins = @import("mods/mod.zig").builtins;
const chameleon = @import("chameleon");
const fmt = @import("fmt.zig");
const toml = @import("toml");
pub const shell = @import("shell/mod.zig");
pub const env = @import("env.zig");
const ThreadCtx = @import("util/ThreadCtx.zig");

const git = @import("mods/git.zig");
const log = std.log.scoped(.root);

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

        const writer = arr.writer(alloc);

        if (dur_ms >= DAY) {
            const days = dur_ms / DAY;
            try writer.print("{d}d", .{days});
            dur_ms %= DAY;
        }

        if (dur_ms >= HOUR) {
            const hours = dur_ms / HOUR;
            try writer.print("{d}h", .{hours});
            dur_ms %= HOUR;
        }

        if (dur_ms >= MIN) {
            const mins = dur_ms / MIN;
            try writer.print("{d}m", .{mins});
            dur_ms %= MIN;
        }

        if (dur_ms >= SEC) {
            const secs = dur_ms / SEC;
            try writer.print("{d}s", .{secs});
            dur_ms %= SEC;
        }

        // 只有在无其他单位且 > 100ms 时显示
        if (dur_ms > 100 and arr.items.len == 0) {
            try writer.print("{d}ms", .{dur_ms});
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
    timeout_ms: u64 = 500, // TODO: make it works

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !App {
        env.init();
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

    /// Execute commands and collect their results
    fn executeCommands(self: *App, results: [][]const u8) !void {
        var wg = std.Thread.WaitGroup{};

        // Second pass: evaluate commands that are needed
        for (self.cmds.items, results) |*cmd, *res| {
            if (!try cmd.needsEval(self.alloc)) continue;

            wg.spawnManager(struct {
                fn f(alloc: std.mem.Allocator, c: *Cmd, result_ptr: *[]const u8) void {
                    const r = c.eval(alloc) catch {
                        result_ptr.* = "";
                        return;
                    };
                    result_ptr.* = r;
                }
            }.f, .{ self.alloc, cmd, res });
        }

        wg.wait();

        for (self.cmds.items) |cmd| {
            if (env.DEBUG_MODE and cmd.stats.neesds_eval and (cmd.stats.eval_duration_ms orelse 1) > 1) {
                log.info("time usage: [{s}]\tcheck={d}ms\teval={d}ms", .{
                    cmd.name,
                    cmd.stats.check_duration_ms orelse 0,
                    cmd.stats.eval_duration_ms orelse 0,
                });
            }

            if (!cmd.stats.neesds_eval) continue;
            if (cmd.stats.eval_duration_ms) |dur| {
                if (dur > self.timeout_ms)
                    log.warn("[{s}] took too long: {d} ms", .{ cmd.name, dur });
            }
        }
    }

    /// Format and write command results to the writer
    fn writeCommandResults(self: *App, writer: *std.Io.Writer, results: []const []const u8) !void {
        for (self.cmds.items, results) |_, res| {
            if (res.len == 0) continue;
            _ = try writer.writeAll(res);
            _ = try writer.writeByte(' ');
        }
    }

    /// Write timing information if available
    fn writeTiming(self: *App, writer: *std.Io.Writer) !void {
        const lastDur = try self.shell_state.lastDurationMs(self.alloc);
        defer self.alloc.free(lastDur);
        if (lastDur.len != 0) {
            try self.formatter.gray().print(writer, "󱎫 {s}", .{lastDur});
        }
    }

    /// Write job count if any background jobs are running
    fn writeJobCount(self: *App, writer: *std.Io.Writer) !void {
        if (self.shell_state.jobs) |jobs| {
            if (!std.mem.eql(u8, jobs, "0")) {
                try self.formatter.blue().print(writer, " {s} ", .{jobs});
            }
        }
    }

    /// Write the prompt symbol with appropriate color based on exit code
    fn writePromptSymbol(self: *App, writer: *std.Io.Writer) !void {
        const prompt_symbol = "󱙝 ";

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
    }

    /// Write final prompt output with shell-specific processing
    fn writeFinalOutput(self: *App, out: *std.io.Writer, content: []const u8) !void {
        if (std.mem.eql(u8, self.shell_state.shell, "zsh")) {
            const final_str = try shell.wrapAnsiForZsh(self.alloc, content);
            defer self.alloc.free(final_str);
            try out.writeAll(final_str);
        } else {
            try out.writeAll(content);
        }
    }

    pub fn run(self: *App, out: *std.io.Writer) !void {
        const start_time = if (env.DEBUG_MODE) std.time.milliTimestamp() else 0;
        defer if (env.DEBUG_MODE) {
            const end_time = std.time.milliTimestamp();
            const duration = end_time - start_time;
            log.info("prompt generation took {d} ms", .{duration});
        };

        var buf = std.io.Writer.Allocating.init(self.alloc);
        defer buf.deinit();

        var writer = &buf.writer;
        _ = try writer.writeByte('\n');

        // Run commands in parallel for better performance
        const results = try self.alloc.alloc([]const u8, self.cmds.items.len);
        for (results) |*res| {
            res.* = "";
        }
        defer {
            for (results) |res| {
                if (res.len > 0) self.alloc.free(res);
            }
            self.alloc.free(results);
        }

        // Execute commands and collect results
        try self.executeCommands(results);
        try self.writeCommandResults(writer, results);

        // Write timing and status information
        try self.writeTiming(writer);
        _ = try writer.writeByte('\n');
        try self.writeJobCount(writer);
        try self.writePromptSymbol(writer);

        // Get final buffer and write with shell-specific processing
        const buf_slice = buf.written();
        try self.writeFinalOutput(out, buf_slice);
    }
};

test {
    // 这行代码会让 Zig 递归地去检查并运行上面所有被引用(public)容器里的测试
    std.testing.refAllDecls(@This());
}
