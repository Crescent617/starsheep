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
    const start_time = std.time.milliTimestamp();
    _ = git.git_libgit2_init();
    const inited = std.time.milliTimestamp();
    std.log.debug("libgit2 initialized in {d} ms", .{inited - start_time});
    git_repo_cache = GitRepoCache.init();
    const cache_time = std.time.milliTimestamp();
    std.log.debug("GitRepoCache initialized in {d} ms", .{cache_time - inited});
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

// Bit flags for git status
const STAGED: u8 = 1 << 0; // 0b00000001
const UNSTAGED: u8 = 1 << 1; // 0b00000010
const UNTRACKED: u8 = 1 << 2; // 0b00000100
const DELETED: u8 = 1 << 3; // 0b00001000
const STASHED: u8 = 1 << 4; // 0b00010000
const CONFLICTED: u8 = 1 << 5; // 0b00100000

pub const GitStatus = struct {
    flags: u8 = 0,
    ahead: usize = 0,
    behind: usize = 0,

    fn deinit(_: *const GitStatus, _: std.mem.Allocator) void {
        // noop
    }

    // Helper methods to check flags
    fn isSet(self: *const GitStatus, flag: u8) bool {
        return (self.flags & flag) != 0;
    }

    fn setFlag(self: *GitStatus, flag: u8) void {
        self.flags |= flag;
    }

    fn clearFlag(self: *GitStatus, flag: u8) void {
        self.flags &= ~flag;
    }

    // Property getters
    fn staged(self: *const GitStatus) bool {
        return self.isSet(STAGED);
    }

    fn unstaged(self: *const GitStatus) bool {
        return self.isSet(UNSTAGED);
    }

    fn untracked(self: *const GitStatus) bool {
        return self.isSet(UNTRACKED);
    }

    fn deleted(self: *const GitStatus) bool {
        return self.isSet(DELETED);
    }

    fn stashed(self: *const GitStatus) bool {
        return self.isSet(STASHED);
    }

    fn conflicted(self: *const GitStatus) bool {
        return self.isSet(CONFLICTED);
    }

    fn statusStr(self: *const GitStatus, alloc: std.mem.Allocator) ![]const u8 {
        const is_empty = std.meta.eql(self.*, GitStatus{});
        if (is_empty) {
            return "";
        }

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(alloc);

        try buf.ensureTotalCapacity(alloc, 10);

        if (self.untracked()) {
            try buf.appendSlice(alloc, "?");
        }
        if (self.unstaged()) {
            try buf.appendSlice(alloc, "!");
        }
        if (self.staged()) {
            try buf.appendSlice(alloc, "+");
        }
        if (self.deleted()) {
            try buf.appendSlice(alloc, "✘");
        }
        if (self.conflicted()) {
            try buf.appendSlice(alloc, " ");
        }
        if (self.stashed()) {
            try buf.appendSlice(alloc, "$");
        }

        if (self.ahead > 0) {
            try buf.appendSlice(alloc, "󰁞");
            // Optionally append the number
            if (self.ahead > 1) {
                try std.fmt.format(buf.writer(alloc), "{d}", .{self.ahead});
            }
        }
        if (self.behind > 0) {
            try buf.appendSlice(alloc, "󰁆");
            // Optionally append the number
            if (self.behind > 1) {
                try std.fmt.format(buf.writer(alloc), "{d}", .{self.behind});
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
    try fillStashStats(repo, &res);
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
    try fillStashStats(repo.?, &res);
    return res;
}

fn fillFileStats(repo: *git.git_repository, res: *GitStatus) !void {
    const start_time = std.time.milliTimestamp();
    defer {
        const end_time = std.time.milliTimestamp();
        std.log.debug(
            "fillFileStats took {d} ms",
            .{end_time - start_time},
        );
    }

    const Payload = struct {
        idx: usize = 0,
        res: *GitStatus,
    };

    var payload = Payload{ .res = res };

    const cb = struct {
        fn call(
            path: [*c]const u8,
            status: c_uint,
            payload_ptr: ?*anyopaque,
        ) callconv(.c) c_int {
            _ = path;

            var p: *Payload = @ptrCast(@alignCast(payload_ptr.?));
            p.idx += 1;
            if (p.idx > 1000) return 1;

            const r = p.res;

            if ((status & git.GIT_STATUS_CONFLICTED) != 0)
                r.setFlag(CONFLICTED);

            if ((status & (git.GIT_STATUS_INDEX_NEW |
                git.GIT_STATUS_INDEX_MODIFIED |
                git.GIT_STATUS_INDEX_DELETED)) != 0)
                r.setFlag(STAGED);

            if ((status & (git.GIT_STATUS_INDEX_DELETED |
                git.GIT_STATUS_WT_DELETED)) != 0)
                r.setFlag(DELETED);

            if ((status & (git.GIT_STATUS_WT_MODIFIED |
                git.GIT_STATUS_WT_DELETED)) != 0)
                r.setFlag(UNSTAGED);

            if ((status & git.GIT_STATUS_WT_NEW) != 0)
                r.setFlag(UNTRACKED);

            const all =
                STAGED | UNSTAGED | UNTRACKED | DELETED | CONFLICTED;
            if (r.flags == all) return 1;

            return 0;
        }
    }.call;

    var status_options = std.mem.zeroInit(git.git_status_options, .{});
    status_options.version = git.GIT_STATUS_OPTIONS_VERSION;
    status_options.show = git.GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
    status_options.flags =
        git.GIT_STATUS_OPT_INCLUDE_UNTRACKED |
        git.GIT_STATUS_OPT_EXCLUDE_SUBMODULES |
        git.GIT_STATUS_OPT_DISABLE_PATHSPEC_MATCH;

    if (git.git_status_foreach_ext(
        repo,
        &status_options,
        cb,
        &payload,
    ) < 0) {
        return error.GitStatusError;
    }
}

fn fillStashStats(repo: *git.git_repository, res: *GitStatus) !void {
    const start_time = std.time.milliTimestamp();
    defer {
        const end_time = std.time.milliTimestamp();
        std.log.debug("fillStashStats took {d} ms", .{end_time - start_time});
    }
    // 使用 git_revparse_single 检查是否存在 stash ref
    var object: ?*git.git_object = null;
    defer {
        // 确保总是释放对象（如果存在）
        if (object) |obj| {
            git.git_object_free(obj);
        }
    }

    const result = git.git_revparse_single(&object, repo, "refs/stash");
    if (result == 0) {
        res.setFlag(STASHED); // 找到 stash
    }
}

fn fillPushPullStats(repo: *git.git_repository, res: *GitStatus) !void {
    const start_time = std.time.milliTimestamp();
    defer {
        const end_time = std.time.milliTimestamp();
        std.log.debug("fillPushPullStats took {d} ms", .{end_time - start_time});
    }
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

    const nonGitResult = try getGitStatus(allocator, "/tmp");
    try testing.expect(nonGitResult == null);
}
