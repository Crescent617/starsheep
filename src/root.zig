//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const Cmd = @import("Cmd.zig");
pub const Conf = @import("conf.zig").AppConf;
const builtins = @import("builtin/mod.zig").builtins;
const chameleon = @import("chameleon");
const fmt = @import("fmt.zig");

pub const App = struct {
    cmds: std.ArrayList(Cmd),
    alloc: std.mem.Allocator,
    formatter: chameleon.RuntimeChameleon,

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
    }

    pub fn applyConfig(self: *App, cfg: *const Conf) !void {
        var cmd_map = std.StringHashMap(*Cmd).init(self.alloc);
        defer cmd_map.deinit();

        // 方法2: 使用指针算术
        for (self.cmds.items, 0..) |_, i| {
            _ = try cmd_map.put(self.cmds.items[i].name, &self.cmds.items[i]);
        }

        var alloc = self.alloc;

        for (cfg.cmds) |cmd_conf| {
            if (cmd_map.get(cmd_conf.name)) |existing_cmd| {
                existing_cmd.enabled = cmd_conf.enabled orelse existing_cmd.enabled;
                existing_cmd.format = cmd_conf.format orelse existing_cmd.format;
            } else {
                const cmd = Cmd{
                    .name = try alloc.dupe(u8, cmd_conf.name),
                    .cmd = .{ .L = try alloc.dupe(u8, cmd_conf.cmd) },
                    .when = .{ .L = if (cmd_conf.when) |w| try alloc.dupe(u8, w) else "" },
                    .format = if (cmd_conf.format) |f| try alloc.dupe(u8, f) else null,
                    .enabled = cmd_conf.enabled orelse true,
                };
                try self.cmds.append(alloc, cmd);
            }
        }
    }

    pub fn run(self: *App, writer: *std.io.Writer) !void {
        for (self.cmds.items, 0..) |cmd, i| {
            if (!try cmd.needsEval(self.alloc)) continue;

            const res = try cmd.eval(self.alloc);

            try fmt.format(self.alloc, cmd.format, res, &self.formatter, writer);

            if (i != self.cmds.items.len - 1) {
                _ = try writer.writeByte(' ');
            }
        }
    }
};

test {
    // 这行代码会让 Zig 递归地去检查并运行上面所有被引用(public)容器里的测试
    std.testing.refAllDecls(@This());
}
