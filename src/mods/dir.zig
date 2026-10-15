const std = @import("std");
const util = @import("util.zig");
const env = @import("../env.zig");
const Ctx = @import("../util/Ctx.zig");

pub fn curDir(ctx: Ctx, alloc: std.mem.Allocator) []const u8 {
    // Get current working directory
    // 注意：返回值会被调用方 free，不能用字符串字面量
    const cwd = std.Io.Dir.cwd().realPathFileAlloc(env.io(), ".", alloc) catch return alloc.dupe(u8, "|error|") catch "";
    defer alloc.free(cwd);

    // Find .git directory upwards
    if (util.findFileUpwards(alloc, ".", ".git")) |git_dir| {
        defer git_dir.deinit(alloc);

        // Get the git repository root (parent of .git)
        const git_root = std.Io.Dir.path.dirname(git_dir.path) orelse "";

        // If current directory is the git root, return basename
        if (std.mem.eql(u8, cwd, git_root)) {
            return alloc.dupe(u8, std.Io.Dir.path.basename(cwd)) catch (alloc.dupe(u8, "|error|") catch "");
        }

        // If current directory is inside git repository, preserve relative path
        if (std.mem.startsWith(u8, cwd, git_root)) {
            // Calculate the relative path from git root
            const relative_path = cwd[git_root.len..];
            return std.Io.Dir.path.join(alloc, &.{ std.Io.Dir.path.basename(git_root), relative_path }) catch (alloc.dupe(u8, "|error|") catch "");
        }
    }

    // Fallback to regular current directory handling
    return getCurrentDir(ctx, alloc) catch (alloc.dupe(u8, "|error|") catch "");
}

fn getCurrentDir(_: Ctx, allocator: std.mem.Allocator) ![]const u8 {
    // 1. 获取当前工作目录的绝对路径
    // realPathFileAlloc 返回 [:0]u8，其底层分配比 slice 长 1（哨兵字节），
    // 直接返回会在调用方 free 时长度对不上，这里转成普通 []u8
    const raw = try std.Io.Dir.cwd().realPathFileAlloc(env.io(), ".", allocator);
    defer allocator.free(raw);
    const cwd = try allocator.dupe(u8, raw);
    errdefer allocator.free(cwd);

    // 2. 获取 HOME 环境变量
    // 在 NixOS/Linux 上通常是 /home/username
    const home = env.getenv("HOME") orelse {
        return cwd; // 找不到 HOME，直接返回原路径
    };

    // 3. 检查 cwd 是否以 home 开头
    if (std.mem.startsWith(u8, cwd, home)) {
        // 计算剩余部分的路径 (例如: /home/user/project -> /project)
        const relative_path = cwd[home.len..];

        // 释放原始 cwd，分配带 ~ 的新字符串
        defer allocator.free(cwd);
        return try allocator.print("~{s}", .{relative_path});
    }

    return cwd;
}

test "getCurrentDir returns path with ~ for home directory" {
    const allocator = std.testing.allocator;

    const original_cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(original_cwd);

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    const result = try getCurrentDir(.{}, allocator);
    defer allocator.free(result);

    if (std.mem.startsWith(u8, result, "~")) {
        // 结果以 ~ 开头，符合预期
        return;
    } else {
        try std.testing.expect(false);
    }
}
