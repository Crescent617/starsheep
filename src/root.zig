//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const Cmd = @import("Cmd.zig");
pub const Conf = @import("conf.zig").AppConf;
const builtins = @import("builtin/mod.zig").builtins;
const chameleon = @import("chameleon");
const fmt = @import("fmt.zig");
const toml = @import("toml");

pub const App = struct {
    cmds: std.ArrayList(Cmd),
    alloc: std.mem.Allocator,
    formatter: chameleon.RuntimeChameleon,
    parsed_conf: ?toml.Parsed(Conf) = null,

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
            } else {
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

    pub fn run(self: *App, writer: *std.io.Writer) !void {
        var is_first = true;

        for (self.cmds.items) |cmd| {
            if (!try cmd.needsEval(self.alloc)) continue;

            const res = try cmd.eval(self.alloc);
            defer self.alloc.free(res);

            if (res.len == 0) continue;

            if (!is_first) {
                _ = try writer.writeByte(' ');
            } else {
                is_first = false;
            }
            try fmt.format(self.alloc, cmd.format, res, &self.formatter, writer);
        }
    }
};

test {
    // 这行代码会让 Zig 递归地去检查并运行上面所有被引用(public)容器里的测试
    std.testing.refAllDecls(@This());
}
