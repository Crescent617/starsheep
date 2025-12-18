const std = @import("std");

pub const PathInfo = struct {
    stat: std.fs.File.Stat,
    path: []const u8,

    fn deinit(self: *const PathInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

pub fn statFileUpwards(allocator: std.mem.Allocator, start_dir: []const u8, filename: []const u8) ?PathInfo {
    // 先规范化为绝对路径，避免 ".." 等造成判断异常
    const p = std.fs.cwd().realpathAlloc(allocator, start_dir) catch return null;
    defer allocator.free(p);

    var cur: []const u8 = p;

    while (true) {
        if (statFile(allocator, cur, filename)) |res| {
            return PathInfo{
                .stat = res,
                .path = std.fs.path.join(allocator, &.{ cur, filename }) catch return null,
            };
        }

        const parent = std.fs.path.dirname(cur) orelse break;

        // 根目录时 dirname 往往返回自身，避免死循环
        if (std.mem.eql(u8, parent, cur)) break;

        cur = parent;
    }

    return null;
}

pub fn existsFileUpwards(allocator: std.mem.Allocator, start_dir: []const u8, filename: []const u8) bool {
    const res = statFileUpwards(allocator, start_dir, filename);
    if (res) |p| {
        p.deinit(allocator);
        return true;
    }
    return false;
}

fn statFile(allocator: std.mem.Allocator, base: []const u8, child: []const u8) ?std.fs.File.Stat {
    const full = std.fs.path.join(allocator, &.{ base, child }) catch return null;
    defer allocator.free(full);

    const stat = std.fs.cwd().statFile(full) catch {
        return null;
    };
    return stat;
}

test "existsFileUpwards finds file in parent directories" {
    const allocator = std.testing.allocator;

    // 创建临时目录结构
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // 创建文件在根目录
    const marker_file = try tmp.dir.createFile("marker.txt", .{});
    marker_file.close();

    // 创建嵌套子目录
    try tmp.dir.makePath("a/b/c");

    // 获取深层目录的绝对路径
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const deep_path = try std.fs.path.join(allocator, &.{ tmp_path, "a/b/c" });
    defer allocator.free(deep_path);

    // 测试：应该能在上层目录找到 marker.txt
    const found = existsFileUpwards(allocator, deep_path, "marker.txt");
    try std.testing.expect(found);
}

test "existsFileUpwards finds dir in parent directories" {
    const allocator = std.testing.allocator;

    // 创建临时目录结构
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // 创建嵌套子目录
    try tmp.dir.makePath("a/b/c");

    try tmp.dir.makePath("a/.git");

    // 获取深层目录的绝对路径
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const deep_path = try std.fs.path.join(allocator, &.{ tmp_path, "a/b/c" });
    defer allocator.free(deep_path);

    // 测试：应该能在上层目录找到 .git
    const found = existsFileUpwards(allocator, deep_path, ".git");
    try std.testing.expect(found);
}

test "existsFileUpwards returns false when file not found" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("subdir");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const sub_path = try std.fs.path.join(allocator, &.{ tmp_path, "subdir" });
    defer allocator.free(sub_path);

    const found = existsFileUpwards(allocator, sub_path, "nonexistent.txt");
    try std.testing.expect(!found);
}

test "existsFileUpwards finds file in current directory" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const file = try tmp.dir.createFile("local.txt", .{});
    file.close();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const found = existsFileUpwards(allocator, tmp_path, "local.txt");
    try std.testing.expect(found);
}

test "existsFileUpwards with relative start_dir" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // 创建标记文件
    const marker = try tmp.dir.createFile(".gitignore", .{});
    marker.close();

    // 创建子目录
    try tmp.dir.makePath("src");

    // 保存原始工作目录
    var original_dir = try std.fs.cwd().openDir(".", .{});
    defer original_dir.close();

    // 切换到临时目录
    try tmp.dir.setAsCwd();
    defer original_dir.setAsCwd() catch {};

    // 使用相对路径测试
    const found = existsFileUpwards(allocator, "src", ".gitignore");
    try std.testing.expect(found);
}
