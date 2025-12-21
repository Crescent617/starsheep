const std = @import("std");
const chameleon = @import("chameleon");

pub fn format(
    alloc: std.mem.Allocator,
    format_str: ?[]const u8,
    out: []const u8,
    c: *chameleon.RuntimeChameleon,
    w: *std.io.Writer,
) !void {
    const fmt = format_str orelse {
        try w.writeAll(out);
        return;
    };

    var i: usize = 0;
    var arr: std.ArrayList(u8) = .empty;
    arr.ensureTotalCapacity(alloc, fmt.len) catch {};
    defer arr.deinit(alloc);

    while (i < fmt.len) {
        if (fmt[i] == '#') {
            // 1. 处理 #[fg=red,bg=black,bold]
            if (fmt[i + 1] == '[') {
                if (std.mem.indexOfScalarPos(u8, fmt, i + 2, ']')) |end_idx| {
                    // 先打印之前缓存的内容
                    try c.print(w, "{s}", .{arr.items});
                    arr.clearRetainingCapacity();

                    const style_content = fmt[i + 2 .. end_idx];
                    try applyChameleonStyle(style_content, c);
                    i = end_idx + 1;
                    continue;
                }
            }
        } else if (fmt[i] == '$') {
            if (i + 1 < fmt.len) {
                // 2. 处理 $output 变量替换
                if (std.mem.startsWith(u8, fmt[i + 1 ..], "output")) {
                    try arr.appendSlice(alloc, out);
                    while (arr.getLastOrNull()) |last_char| {
                        if (last_char == '\n') {
                            // 去掉结尾的换行，避免多余空行
                            _ = arr.pop();
                        } else {
                            break;
                        }
                    }
                    // 打印完变量后，通常需要重置样式以防污染后续输出
                    // 如果 chameleon 没有自动重置，可以手动 w.writeAll("\x1b[0m")
                    i += "output".len + 1;
                    continue;
                }
            }
        }

        try arr.append(alloc, fmt[i]);
        i += 1;
    }

    if (arr.items.len > 0) {
        try c.print(w, "{s}", .{arr.items});
    }
}

/// 解析类似 "fg=red,bold" 的字符串并调用 chameleon
fn applyChameleonStyle(content: []const u8, c: *chameleon.RuntimeChameleon) !void {
    var iter = std.mem.tokenizeScalar(u8, content, ',');
    while (iter.next()) |item| {
        if (std.mem.eql(u8, item, "bold")) {
            _ = c.bold();
        } else if (std.mem.startsWith(u8, item, "fg=")) {
            const color = item[3..];
            _ = applyColor(c, color, true);
        } else if (std.mem.startsWith(u8, item, "bg=")) {
            const color = item[3..];
            _ = applyColor(c, color, false);
        } else if (std.mem.eql(u8, item, "italic")) {
            _ = c.italic();
            // 注意：chameleon 的 runtime 状态也需要重置，具体取决于库的实现
        }
    }
}

fn applyColor(c: *chameleon.RuntimeChameleon, color: []const u8, is_fg: bool) *chameleon.RuntimeChameleon {
    // 这种写法最清晰，虽然内部仍然是比较，但维护成本极低
    const ColorTag = enum {
        black,
        red,
        green,
        yellow,
        blue,
        magenta,
        cyan,
        white,
        gray,
        blackBright,
        redBright,
        greenBright,
        yellowBright,
        blueBright,
        magentaBright,
        cyanBright,
        whiteBright,
        unknown,
    };

    const tag = std.meta.stringToEnum(ColorTag, color) orelse .unknown;

    return switch (tag) {
        .black => if (is_fg) c.black() else c.bgBlack(),
        .red => if (is_fg) c.red() else c.bgRed(),
        .green => if (is_fg) c.green() else c.bgGreen(),
        .yellow => if (is_fg) c.yellow() else c.bgYellow(),
        .blue => if (is_fg) c.blue() else c.bgBlue(),
        .magenta => if (is_fg) c.magenta() else c.bgMagenta(),
        .cyan => if (is_fg) c.cyan() else c.bgCyan(),
        .white => if (is_fg) c.white() else c.bgWhite(),
        .gray => if (is_fg) c.gray() else c.bgGray(),
        .blackBright => if (is_fg) c.blackBright() else c.bgBlackBright(),
        .redBright => if (is_fg) c.redBright() else c.bgRedBright(),
        .greenBright => if (is_fg) c.greenBright() else c.bgGreenBright(),
        .yellowBright => if (is_fg) c.yellowBright() else c.bgYellowBright(),
        .blueBright => if (is_fg) c.blueBright() else c.bgBlueBright(),
        .magentaBright => if (is_fg) c.magentaBright() else c.bgMagentaBright(),
        .cyanBright => if (is_fg) c.cyanBright() else c.bgCyanBright(),
        .whiteBright => if (is_fg) c.whiteBright() else c.bgWhiteBright(),
        .unknown => c,
    };
}
