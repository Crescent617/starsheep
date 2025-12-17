const std = @import("std");
const starsheep = @import("starsheep");
const chameleon = @import("chameleon");

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try starsheep.bufferedPrint();

    // Chameleon example - colorful terminal output
    std.debug.print("\n=== Chameleon Examples ===\n", .{});

    // Example 1: Basic colors using comptime
    comptime var c = chameleon.initComptime();
    std.debug.print("{s} {s} {s}\n", .{
        c.red().fmt("Red"),
        c.blue().fmt("Blue"),
        c.green().fmt("Green"),
    });

    // Example 2: Background colors
    std.debug.print("{s} {s}\n", .{
        c.bgYellow().fmt("Yellow background"),
        c.bgMagenta().fmt("Magenta background"),
    });

    // Example 3: Styles
    std.debug.print("{s} {s} {s}\n", .{
        c.bold().fmt("Bold"),
        c.italic().fmt("Italic"),
        c.underline().fmt("Underline"),
    });

    // Example 4: Combining styles
    std.debug.print("{s} {s}\n", .{
        c.bold().red().fmt("Bold red"),
        c.italic().blue().bgCyan().fmt("Italic blue on cyan"),
    });

    // Example 5: More complex combinations
    std.debug.print("{s}\n", .{c.bold().underline().green().fmt("Bold underlined green header")});

    // Example 6: Print methods
    try c.bold().magenta().printOut("Bold magenta using printOut\n", .{});

    // Example 7: Runtime API with NO_COLOR support
    var runtime_chameleon = chameleon.initRuntime(.{
        .allocator = std.heap.page_allocator,
        .detect_no_color = true,
    });
    defer runtime_chameleon.deinit();

    // Runtime styles work the same way as comptime but need format args
    const runtime_text = try runtime_chameleon.bold().green().fmt("{s}", .{"Runtime style (respects NO_COLOR env var)"});
    defer std.heap.page_allocator.free(runtime_text);
    std.debug.print("{s}\n", .{runtime_text});
}
