//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const Cmd = @import("Cmd.zig");
pub const conf = @import("conf.zig");

const App = struct {
    cmds: []Cmd,
};

test {
    // 这行代码会让 Zig 递归地去检查并运行上面所有被引用(public)容器里的测试
    std.testing.refAllDecls(@This());
}
