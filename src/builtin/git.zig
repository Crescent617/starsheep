const std = @import("std");
const util = @import("util.zig");
const git = @cImport({
    @cInclude("git2.h");
});

pub const Err = error{
    GitHeadError,
    GitStatusError,
};

fn init() void {
    _ = git.git_libgit2_init();
    git_repo_cache = GitRepoCache.init();
    libgit2_initialized = true;
}

var ensureGit2Inited = std.once(init);

pub fn deinit() void {
    if (git_repo_cache) |*cache| {
        cache.deinit();
        git_repo_cache = null;
    }
    if (libgit2_initialized) {
        _ = git.git_libgit2_shutdown();
        libgit2_initialized = false;
    }
}

// Cache for git repository state to avoid repeated initialization
var git_repo_cache: ?GitRepoCache = null;
var libgit2_initialized = false;

const GitRepoCache = struct {
    repo: *git.git_repository,
    path: []const u8,
    is_valid: bool,

    fn init() ?GitRepoCache {
        var repo: ?*git.git_repository = null;
        const open_err = git.git_repository_open_ext(&repo, ".", 0, null);
        if (open_err < 0) return null;

        return GitRepoCache{
            .repo = repo.?,
            .path = ".",
            .is_valid = true,
        };
    }

    fn deinit(self: *GitRepoCache) void {
        if (self.is_valid) {
            git.git_repository_free(self.repo);
            self.is_valid = false;
        }
    }
};

pub fn gitStatus(allocator: std.mem.Allocator) []const u8 {
    ensureGit2Inited.call();
    if (git_repo_cache == null or !git_repo_cache.?.is_valid) return "";

    const s = (getGitStatusCached(allocator) catch |err| {
        std.log.err("Failed to get git status: {}\n", .{err});
        return "";
    }) orelse return "";
    defer s.deinit(allocator);
    return s.statusStr(allocator) catch |err| {
        std.log.err("Failed to format git status: {}\n", .{err});
        return "";
    };
}

pub fn gitState(allocotor: std.mem.Allocator) []const u8 {
    ensureGit2Inited.call();
    if (git_repo_cache == null or !git_repo_cache.?.is_valid) return "";

    const repo = git_repo_cache.?.repo;

    const state: RepoState = @enumFromInt(git.git_repository_state(repo));
    const res = switch (state) {
        .MERGE => " MERGING",
        .REBASE, .REBASE_INTERACTIVE, .REBASE_MERGE => " REBASE",
        .CHERRYPICK, .CHERRYPICK_SEQUENCE => " CHERRY-PICK",
        .REVERT, .REVERT_SEQUENCE => " REVERT",
        .BISECT => "󰈞 BISECT",
        .APPLY_MAILBOX, .APPLY_MAILBOX_OR_REBASE => " AM",
        else => "",
    };
    return allocotor.dupe(u8, res) catch "";
}

pub fn gitBranch(allocator: std.mem.Allocator) []const u8 {
    ensureGit2Inited.call();
    if (git_repo_cache == null or !git_repo_cache.?.is_valid) return "";

    const repo = git_repo_cache.?.repo;
    var head: ?*git.git_reference = null;
    const head_err = git.git_repository_head(&head, repo);

    // 处理空仓库情况（没有提交就没有 HEAD）
    if (head_err == git.GIT_ENOTFOUND) return "empty";
    if (head_err < 0) return "";
    defer git.git_reference_free(head);

    // 2. 检查是否为游离状态 (Detached HEAD)
    if (git.git_repository_head_detached(repo) == 1) {
        const oid = git.git_reference_target(head);
        var out: [8]u8 = undefined;
        // 获取 short hash (前 7 位)
        _ = git.git_oid_tostr(&out, out.len, oid);
        return allocator.dupe(u8, std.mem.sliceTo(&out, 0)) catch "";
    }

    // 3. 正常分支，获取简短名称 (如 "main")
    // git_reference_shorthand 返回的是 [*c]const u8
    const name_c = git.git_reference_shorthand(head);
    if (name_c == null) return "";

    // 将 C 指针转为 Zig 切片并克隆，因为 head 释放后 name_c 指向的内存会失效
    return allocator.dupe(u8, std.mem.span(name_c)) catch "";
}

const RepoState = enum(u32) {
    NONE = git.GIT_REPOSITORY_STATE_NONE,
    MERGE = git.GIT_REPOSITORY_STATE_MERGE,
    REVERT = git.GIT_REPOSITORY_STATE_REVERT,
    REVERT_SEQUENCE = git.GIT_REPOSITORY_STATE_REVERT_SEQUENCE,
    CHERRYPICK = git.GIT_REPOSITORY_STATE_CHERRYPICK,
    CHERRYPICK_SEQUENCE = git.GIT_REPOSITORY_STATE_CHERRYPICK_SEQUENCE,
    BISECT = git.GIT_REPOSITORY_STATE_BISECT,
    REBASE = git.GIT_REPOSITORY_STATE_REBASE,
    REBASE_INTERACTIVE = git.GIT_REPOSITORY_STATE_REBASE_INTERACTIVE,
    REBASE_MERGE = git.GIT_REPOSITORY_STATE_REBASE_MERGE,
    APPLY_MAILBOX = git.GIT_REPOSITORY_STATE_APPLY_MAILBOX,
    APPLY_MAILBOX_OR_REBASE = git.GIT_REPOSITORY_STATE_APPLY_MAILBOX_OR_REBASE,
};

pub const GitStatus = struct {
    staged: usize = 0,
    unstaged: usize = 0,
    untracked: usize = 0,
    deleted: usize = 0,
    ahead: usize = 0,
    behind: usize = 0,

    fn deinit(_: *const GitStatus, _: std.mem.Allocator) void {
        // noop
    }

    fn statusStr(self: *const GitStatus, alloc: std.mem.Allocator) ![]const u8 {
        const is_empty = std.meta.eql(self.*, GitStatus{});
        if (is_empty) {
            return "";
        }

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(alloc);

        try buf.ensureTotalCapacity(alloc, 6);

        if (self.untracked > 0) {
            try buf.appendSlice(alloc, "?");
        }
        if (self.unstaged > 0) {
            try buf.appendSlice(alloc, "!");
        }
        if (self.staged > 0) {
            try buf.appendSlice(alloc, "+");
        }
        if (self.deleted > 0) {
            try buf.appendSlice(alloc, "✘");
        }

        if (self.ahead > 0 and self.behind > 0) {
            try buf.appendSlice(alloc, "");
        } else {
            if (self.ahead > 0) {
                try buf.appendSlice(alloc, "󰁞");
            }
            if (self.behind > 0) {
                try buf.appendSlice(alloc, "󰁆");
            }
        }
        return try buf.toOwnedSlice(alloc);
    }
};

// Cached version that uses the global repository cache
fn getGitStatusCached(_: std.mem.Allocator) !?GitStatus {
    if (git_repo_cache == null or !git_repo_cache.?.is_valid) return null;

    const repo = git_repo_cache.?.repo;
    var res = GitStatus{};

    try fillFileStats(repo, &res);
    try fillPushPullStats(repo, &res);
    return res;
}

fn getGitStatus(_: std.mem.Allocator, path: []const u8) !?GitStatus {
    // 初始化 libgit2
    _ = git.git_libgit2_init();
    defer _ = git.git_libgit2_shutdown();

    var repo: ?*git.git_repository = null;

    // git_repository_open_ext 能自动向上递归寻找 .git 文件夹，并处理 worktree/submodule
    const open_err = git.git_repository_open_ext(&repo, path.ptr, 0, null);
    if (open_err < 0) return null;
    defer git.git_repository_free(repo);

    var res = GitStatus{};
    try fillFileStats(repo.?, &res);
    try fillPushPullStats(repo.?, &res);
    return res;
}

fn fillFileStats(repo: *git.git_repository, res: *GitStatus) !void {
    var status_options = std.mem.zeroInit(git.git_status_options, .{});
    status_options.version = git.GIT_STATUS_OPTIONS_VERSION;
    // 包含未追踪的文件，并递归遍历子目录
    status_options.flags = git.GIT_STATUS_OPT_INCLUDE_UNTRACKED | git.GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS;

    var status_list: ?*git.git_status_list = null;
    if (git.git_status_list_new(&status_list, repo, &status_options) < 0) return error.GitStatusError;
    defer git.git_status_list_free(status_list);

    const count = git.git_status_list_entrycount(status_list);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const entry = git.git_status_byindex(status_list, i);
        const s = entry.*.status;

        // 统计 Staged (暂存区)
        if ((s & (git.GIT_STATUS_INDEX_NEW | git.GIT_STATUS_INDEX_MODIFIED | git.GIT_STATUS_INDEX_DELETED)) != 0) {
            res.staged += 1;
        }

        // deleted 文件单独统计
        if ((s & (git.GIT_STATUS_INDEX_DELETED | git.GIT_STATUS_WT_DELETED)) != 0) {
            res.deleted += 1;
        }

        // 统计 Unstaged (已修改未暂存)
        if ((s & (git.GIT_STATUS_WT_MODIFIED | git.GIT_STATUS_WT_DELETED)) != 0) {
            res.unstaged += 1;
        }

        // 统计 Untracked (未追踪)
        if ((s & git.GIT_STATUS_WT_NEW) != 0) {
            res.untracked += 1;
        }
    }
}

fn fillPushPullStats(repo: *git.git_repository, res: *GitStatus) !void {
    var head: ?*git.git_reference = null;
    // 获取当前 HEAD
    if (git.git_repository_head(&head, repo) < 0) return;
    defer git.git_reference_free(head);

    // 如果是游离头指针，通常不统计 push/pull
    if (git.git_repository_head_detached(repo) == 1) return;

    // 1. 获取本地分支的 OID
    const local_oid = git.git_reference_target(head);

    // 2. 获取对应的远程追踪分支 (Upstream)
    var upstream: ?*git.git_reference = null;
    if (git.git_branch_upstream(&upstream, head) < 0) {
        // 没有远程分支，直接返回
        return;
    }
    defer git.git_reference_free(upstream);

    const upstream_oid = git.git_reference_target(upstream);

    // 3. 计算 Ahead / Behind
    var ahead: usize = 0;
    var behind: usize = 0;
    if (git.git_graph_ahead_behind(&ahead, &behind, repo, local_oid, upstream_oid) == 0) {
        res.ahead = ahead;
        res.behind = behind;
    }
}

test "fetchGitStatus" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test with current directory (should have a .git folder)
    const result = try getGitStatus(allocator, ".");
    try testing.expect(result != null);

    if (result) |status| {
        defer status.deinit(allocator);

        std.debug.print("{}\n", .{status});
    }

    // Test with non-git directory
    const nonGitResult = try getGitStatus(allocator, "/tmp");
    try testing.expect(nonGitResult == null);
}
