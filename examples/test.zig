const std = @import("std");

const zttio = @import("zttio");
const zweave = @import("zweave");

pub fn main() !u8 {
    var gpa: std.heap.DebugAllocator(.{
        .retain_metadata = true,
        .never_unmap = true,
    }) = .init;
    defer if (gpa.deinit() == .leak) @panic("memory leaks");
    const allocator = gpa.allocator();

    var tty = try zttio.Tty.init(
        allocator,
        allocator,
        .stdin(),
        .stdout(),
        null,
        .{},
    );
    defer tty.deinit();

    try tty.enableAndResetAlternativeScreen();
    defer tty.disableAlternativeScreen() catch {};
    try tty.hideCursor();
    try tty.flush();

    var screen = try zweave.Screen.init(
        allocator,
        tty.getWinsize(),
        tty.caps.unicode_width_method,
    );
    defer screen.deinit();

    while (true) {
        var event = tty.nextEvent();
        defer event.deinit(allocator);

        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                }
            },
            .winsize => |winsize| {
                try screen.resize(winsize);
                screen.clear();

                const offset = try screen.write(0, 0, "width method: ", .{});
                _ = try screen.write(offset, 0, @tagName(screen.width_method), .{});

                const style_1 = try screen.registerStyle(.{
                    .background = .rgb(34, 31, 48),
                    .underline = .{ .style = .curly },
                });

                const link = try screen.registerBlock(.{
                    .hyperlink = .{ .uri = "https://www.google.com" },
                });

                var last_row = screen.view(0, screen.winsize.rows - 1, null, null, .allow_overflow);
                _ = try last_row.write(0, 0, "as", .{
                    .style = style_1,
                    .block = link,
                });
                _ = try last_row.write(0, 1, "test", .{});

                const style_2 = try screen.registerStyle(.{
                    .background = .rgb(34, 31, 48),
                });

                var last_row_2 = last_row.view(3, 0, null, null, .no_overflow);
                _ = try last_row_2.write(0, 0, "👨‍👩‍👧‍👦", .{
                    .style = style_2,
                });

                _ = try last_row.writeCell(4, 0, "t", .{
                    .style = style_2,
                });

                try screen.renderDirect(tty);
                try tty.flush();
            },
            else => {},
        }
    }

    return 0;
}
