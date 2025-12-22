const std = @import("std");

pub const init_zsh_script = @embedFile("init-zsh.sh");

pub fn wrapAnsiForZsh(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        // 检查是否是转义序列的开头 \x1b[ (即 ^[[ )
        if (i + 1 < input.len and input[i] == '\x1b' and input[i + 1] == '[') {
            try result.appendSlice(allocator, "%{");

            // 寻找该转义序列的结尾 'm'
            var found_m = false;
            while (i < input.len) : (i += 1) {
                try result.append(allocator, input[i]);
                if (input[i] == 'm') {
                    found_m = true;
                    i += 1;
                    break;
                }
            }

            if (found_m) {
                try result.appendSlice(allocator, "%}");
            }
        } else {
            // 普通字符，直接添加
            try result.append(allocator, input[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

const testing = std.testing;

test "wrapAnsiForZsh - 基础颜色包裹" {
    const allocator = testing.allocator;

    // 模拟输入: ^[[36mstarsheep^[[0m
    const input = "\x1b[36mstarsheep\x1b[0m";
    const expected = "%{\x1b[36m%}starsheep%{\x1b[0m%}";

    const actual = try wrapAnsiForZsh(allocator, input);
    defer allocator.free(actual);

    try testing.expectEqualStrings(expected, actual);
}

test "wrapAnsiForZsh - 复杂组合与普通文字" {
    const allocator = testing.allocator;

    // 模拟输入: ^[[1;32mOK^[[0m text ^[[34mBlue
    const input = "\x1b[1;32mOK\x1b[0m text \x1b[34mBlue";
    const expected = "%{\x1b[1;32m%}OK%{\x1b[0m%} text %{\x1b[34m%}Blue";

    const actual = try wrapAnsiForZsh(allocator, input);
    defer allocator.free(actual);

    try testing.expectEqualStrings(expected, actual);
}

test "wrapAnsiForZsh - 无颜色代码的普通字符串" {
    const allocator = testing.allocator;

    const input = "pure text";
    const expected = "pure text";

    const actual = try wrapAnsiForZsh(allocator, input);
    defer allocator.free(actual);

    try testing.expectEqualStrings(expected, actual);
}

test "wrapAnsiForZsh - 空字符串" {
    const allocator = testing.allocator;

    const actual = try wrapAnsiForZsh(allocator, "");
    defer allocator.free(actual);

    try testing.expectEqualStrings("", actual);
}
