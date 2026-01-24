const std = @import("std");

/// Format milliseconds into a human-readable string like "1d2h3m4s".
/// If duration is null, zero, or invalid, returns an empty string.
/// Only shows milliseconds if > 100ms and no other units are displayed.
pub fn formatDurationMs(alloc: std.mem.Allocator, duration_ms: ?[]const u8) ![]const u8 {
    if (duration_ms == null) {
        return "";
    }
    const dur_str = duration_ms.?;
    const dur_f = std.fmt.parseFloat(f64, dur_str) catch return "";
    var dur_ms: u64 = @intFromFloat(dur_f);

    if (dur_ms == 0) {
        return "";
    }

    var arr: std.ArrayList(u8) = .empty;
    defer arr.deinit(alloc);

    const DAY: u64 = 1000 * 60 * 60 * 24;
    const HOUR: u64 = 1000 * 60 * 60;
    const MIN: u64 = 1000 * 60;
    const SEC: u64 = 1000;

    const writer = arr.writer(alloc);

    if (dur_ms >= DAY) {
        const days = dur_ms / DAY;
        try writer.print("{d}d", .{days});
        dur_ms %= DAY;
    }

    if (dur_ms >= HOUR) {
        const hours = dur_ms / HOUR;
        try writer.print("{d}h", .{hours});
        dur_ms %= HOUR;
    }

    if (dur_ms >= MIN) {
        const mins = dur_ms / MIN;
        try writer.print("{d}m", .{mins});
        dur_ms %= MIN;
    }

    if (dur_ms >= SEC) {
        const secs = dur_ms / SEC;
        try writer.print("{d}s", .{secs});
        dur_ms %= SEC;
    }

    // Only show milliseconds if > 100ms and no other units are displayed
    if (dur_ms > 100 and arr.items.len == 0) {
        try writer.print("{d}ms", .{dur_ms});
    }
    return try arr.toOwnedSlice(alloc);
}

test "formatDurationMs - null input" {
    const alloc = std.testing.allocator;
    const result = try formatDurationMs(alloc, null);
    defer alloc.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "formatDurationMs - zero milliseconds" {
    const alloc = std.testing.allocator;
    const result = try formatDurationMs(alloc, "0");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "formatDurationMs - invalid input returns empty" {
    const alloc = std.testing.allocator;
    const result = try formatDurationMs(alloc, "invalid");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "formatDurationMs - milliseconds only" {
    const alloc = std.testing.allocator;
    const result = try formatDurationMs(alloc, "150");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("150ms", result);
}

test "formatDurationMs - milliseconds not shown if <= 100" {
    const alloc = std.testing.allocator;
    const result = try formatDurationMs(alloc, "100");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "formatDurationMs - seconds" {
    const alloc = std.testing.allocator;
    const result = try formatDurationMs(alloc, "5000");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("5s", result);
}

test "formatDurationMs - minutes" {
    const alloc = std.testing.allocator;
    const result = try formatDurationMs(alloc, "120000");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("2m", result);
}

test "formatDurationMs - hours" {
    const alloc = std.testing.allocator;
    const result = try formatDurationMs(alloc, "3600000");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("1h", result);
}

test "formatDurationMs - days" {
    const alloc = std.testing.allocator;
    const result = try formatDurationMs(alloc, "86400000");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("1d", result);
}

test "formatDurationMs - combined units" {
    const alloc = std.testing.allocator;
    const result = try formatDurationMs(alloc, "90061000"); // 1d 1h 1m 1s
    defer alloc.free(result);
    try std.testing.expectEqualStrings("1d1h1m1s", result);
}

test "formatDurationMs - multiple days, hours, minutes" {
    const alloc = std.testing.allocator;
    const result = try formatDurationMs(alloc, "172800000"); // 2 days
    defer alloc.free(result);
    try std.testing.expectEqualStrings("2d", result);
}

test "formatDurationMs - floating point input" {
    const alloc = std.testing.allocator;
    const result = try formatDurationMs(alloc, "2500.5");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("2s", result); // Should truncate to 2s
}

test "formatDurationMs - large value" {
    const alloc = std.testing.allocator;
    const result = try formatDurationMs(alloc, "31536000000"); // 365 days
    defer alloc.free(result);
    try std.testing.expectEqualStrings("365d", result);
}