const std = @import("std");
const env = @import("../env.zig");

pub const PathInfo = struct {
    stat: std.Io.File.Stat,
    path: []const u8,

    pub fn deinit(self: *const PathInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

pub fn statFileUpwards(allocator: std.mem.Allocator, start_dir: []const u8, filename: []const u8) ?PathInfo {
    // 先规范化为绝对路径，避免 ".." 等造成判断异常
    const p = std.Io.Dir.cwd().realPathFileAlloc(env.io, start_dir, allocator) catch return null;
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

fn statFile(allocator: std.mem.Allocator, base: []const u8, child: []const u8) ?std.Io.File.Stat {
    const full = std.fs.path.join(allocator, &.{ base, child }) catch return null;
    defer allocator.free(full);

    const stat = std.Io.Dir.cwd().statFile(env.io, full, .{}) catch {
        return null;
    };
    return stat;
}

pub fn runSubprocess(allocator: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
    var child = try std.process.spawn(env.io, .{
        .argv = argv,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    var buf: [4096]u8 = undefined;
    var reader = child.stdout.?.reader(env.io, &buf);
    const out = try reader.interface.allocRemaining(allocator, .unlimited);
    // NOTE: stderr is not drained concurrently; commands are expected to only
    // produce small outputs so the stderr pipe buffer never fills up.
    _ = try child.wait(env.io);
    return out;
}

test "existsFileUpwards finds file in parent directories" {
    const allocator = std.testing.allocator;
    env.initForTest();

    // 创建临时目录结构
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // 创建文件在根目录
    const marker_file = try tmp.dir.createFile(std.testing.io, "marker.txt", .{});
    marker_file.close(std.testing.io);

    // 创建嵌套子目录
    try tmp.dir.createDirPath(std.testing.io, "a/b/c");

    // 获取深层目录的绝对路径
    const tmp_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    defer allocator.free(tmp_path);

    const deep_path = try std.fs.path.join(allocator, &.{ tmp_path, "a/b/c" });
    defer allocator.free(deep_path);

    // 测试：应该能在上层目录找到 marker.txt
    const found = existsFileUpwards(allocator, deep_path, "marker.txt");
    try std.testing.expect(found);
}

test "existsFileUpwards finds dir in parent directories" {
    const allocator = std.testing.allocator;
    env.initForTest();

    // 创建临时目录结构
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // 创建嵌套子目录
    try tmp.dir.createDirPath(std.testing.io, "a/b/c");

    try tmp.dir.createDirPath(std.testing.io, "a/.git");

    // 获取深层目录的绝对路径
    const tmp_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    defer allocator.free(tmp_path);

    const deep_path = try std.fs.path.join(allocator, &.{ tmp_path, "a/b/c" });
    defer allocator.free(deep_path);

    // 测试：应该能在上层目录找到 .git
    const found = existsFileUpwards(allocator, deep_path, ".git");
    try std.testing.expect(found);
}

test "existsFileUpwards returns false when file not found" {
    const allocator = std.testing.allocator;
    env.initForTest();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "subdir");

    const tmp_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    defer allocator.free(tmp_path);

    const sub_path = try std.fs.path.join(allocator, &.{ tmp_path, "subdir" });
    defer allocator.free(sub_path);

    const found = existsFileUpwards(allocator, sub_path, "nonexistent.txt");
    try std.testing.expect(!found);
}

test "existsFileUpwards finds file in current directory" {
    const allocator = std.testing.allocator;
    env.initForTest();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const file = try tmp.dir.createFile(std.testing.io, "local.txt", .{});
    file.close(std.testing.io);

    const tmp_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    defer allocator.free(tmp_path);

    const found = existsFileUpwards(allocator, tmp_path, "local.txt");
    try std.testing.expect(found);
}

test "existsFileUpwards with relative start_dir" {
    const allocator = std.testing.allocator;
    env.initForTest();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // 创建标记文件
    const marker = try tmp.dir.createFile(std.testing.io, ".gitignore", .{});
    marker.close(std.testing.io);

    // 创建子目录
    try tmp.dir.createDirPath(std.testing.io, "src");

    // 保存原始工作目录
    var original_dir = try std.Io.Dir.cwd().openDir(std.testing.io, ".", .{});
    defer original_dir.close(std.testing.io);

    // 切换到临时目录
    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer std.process.setCurrentDir(std.testing.io, original_dir) catch {};

    // 使用相对路径测试
    const found = existsFileUpwards(allocator, "src", ".gitignore");
    try std.testing.expect(found);
}
