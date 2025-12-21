const std = @import("std");
const util = @import("util.zig");

pub fn curDir(alloc: std.mem.Allocator) []const u8 {
    if (util.statFileUpwards(alloc, ".", ".git")) |git_dir| {
        defer git_dir.deinit(alloc);
        var dir_path = std.fs.path.dirname(git_dir.path) orelse "";
        dir_path = std.fs.path.basename(dir_path);
        return alloc.dupe(u8, dir_path) catch "|error|";
    }
    return getCurrentDir(alloc) catch "|error|";
}

fn getCurrentDir(allocator: std.mem.Allocator) ![]const u8 {
    // 1. 获取当前工作目录的绝对路径
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    errdefer allocator.free(cwd);

    // 2. 获取 HOME 环境变量
    // 在 NixOS/Linux 上通常是 /home/username
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| {
        if (err == error.EnvironmentVariableNotFound) {
            return cwd; // 找不到 HOME，直接返回原路径
        }
        return err;
    };
    defer allocator.free(home);

    // 3. 检查 cwd 是否以 home 开头
    if (std.mem.startsWith(u8, cwd, home)) {
        // 计算剩余部分的路径 (例如: /home/user/project -> /project)
        const relative_path = cwd[home.len..];

        // 释放原始 cwd，分配带 ~ 的新字符串
        defer allocator.free(cwd);
        return try std.fmt.allocPrint(allocator, "~{s}", .{relative_path});
    }

    return cwd;
}

test "getCurrentDir returns path with ~ for home directory" {
    const allocator = std.testing.allocator;

    const original_cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(original_cwd);

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    const result = try getCurrentDir(allocator);
    defer allocator.free(result);

    std.debug.print("Original CWD: {s}\n", .{original_cwd});
    std.debug.print("After getCurrentDir: {s}\n", .{result});

    if (std.mem.startsWith(u8, result, "~")) {
        // 结果以 ~ 开头，符合预期
        return;
    } else {
        try std.testing.expect(false);
    }
}
