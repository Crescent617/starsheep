const std = @import("std");
const util = @import("util.zig");

const GIT_HEAD_REF_PREFIX = "ref: refs/heads/";

pub const GitStatus = struct {
    current_branch: []const u8 = "",
    is_detached: bool = false,
    staged: usize = 0,
    unstaged: usize = 0,
    untracked: usize = 0,
    deleted: usize = 0,

    fn deinit(self: *GitStatus, allocator: std.mem.Allocator) void {
        allocator.free(self.current_branch);
    }
};

pub fn fetchGitStatus(allocator: std.mem.Allocator, path: []const u8) !?GitStatus {
    const git_dir = util.statFileUpwards(allocator, path, ".git") orelse return null;

    if (git_dir.stat.kind != .directory) {
        // TODO: handle the case where .git is a file (submodule or worktree)
        return null;
    }

    var res = GitStatus{};

    // Read current branch
    // .git/HEAD 文件内容类似 "ref: refs/heads/main"
    const head_path = try std.fs.path.join(allocator, &.{ git_dir.path, "HEAD" });
    defer allocator.free(head_path);

    const head_file = try std.fs.cwd().openFile(head_path, .{});
    defer head_file.close();

    const head_content = try head_file.readToEndAlloc(allocator, 1024);
    defer allocator.free(head_content);

    const hc_trimmed = std.mem.trim(head_content, " \n\r\t");

    if (std.mem.startsWith(u8, hc_trimmed, GIT_HEAD_REF_PREFIX)) {
        // 情况 A: 正常分支 "ref: refs/heads/main"
        res.current_branch = try allocator.dupe(u8, hc_trimmed[GIT_HEAD_REF_PREFIX.len..]);
    } else {
        // 情况 B: 游离状态 (Detached HEAD)，内容是 Commit Hash
        res.is_detached = true;
        // 通常显示短 Hash (7位)
        const len = if (hc_trimmed.len >= 7) 7 else hc_trimmed.len;
        res.current_branch = try allocator.dupe(u8, hc_trimmed[0..len]);
    }
    return res;
}
