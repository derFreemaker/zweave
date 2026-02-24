const std = @import("std");

const zttio = @import("zttio");
const zweave = @import("zweave");

const Block = struct {
    pub fn element(self: *Block) zweave.Element.Interface {
        return .{ .ptr = self, .vtable = &.{
            .getLayoutConstraints = getLayoutConstraints,
            .draw = draw,
        } };
    }

    pub fn getLayoutConstraints(ctx: *const zweave.Element.GetLayoutConstraintsContext) zweave.Element.GetLayoutConstraintsError!zweave.LayoutConstraints {
        _ = ctx;

        return zweave.LayoutConstraints{
            .height = .{ .percentage = 0.5 },
            .width = .{ .percentage = 1 },
        };
    }

    pub fn draw(ctx: *const zweave.Element.DrawContext) zweave.Element.DrawError!void {
        const view = &ctx.view;

        for (0..view.height) |h| {
            for (0..view.width) |w| {
                _ = try view.writeCell(@intCast(w), @intCast(h), "F", .{});
            }
        }
    }
};

pub fn main() !u8 {
    var gpa: std.heap.DebugAllocator(.{
        .retain_metadata = true,
        .never_unmap = true,
    }) = .init;
    defer if (gpa.deinit() == .leak) @panic("memory leaks");
    const allocator = gpa.allocator();

    // var tty = try zttio.Tty.init(
    //     allocator,
    //     allocator,
    //     .stdin(),
    //     .stdout(),
    //     .{},
    // );
    // defer tty.deinit();

    // try tty.enableAndResetAlternativeScreen();
    // defer tty.disableAlternativeScreen() catch {};
    // try tty.hideCursor();
    // try tty.flush();

    // var screen = try zweave.Screen.init(
    //     allocator,
    //     tty.getWinsize(),
    //     tty.caps.unicode_width_method,
    // );
    // defer screen.deinit();

    // while (true) {
    //     var event = tty.nextEvent();
    //     defer event.deinit(allocator);

    //     switch (event) {
    //         .key_press => |key| {
    //             if (key.matches('c', .{ .ctrl = true })) {
    //                 break;
    //             }
    //         },
    //         .winsize => |winsize| {
    //             try screen.resize(winsize);
    //             screen.clear();

    //             const offset = try screen.write(0, 0, "width method: ", .{});
    //             _ = try screen.write(offset, 0, @tagName(screen.width_method), .{});

    //             const style_1 = try screen.registerStyle(.{
    //                 .background = .rgb(34, 31, 48),
    //                 .underline = .{ .style = .curly },
    //             });

    //             const link = try screen.registerBlock(.{
    //                 .hyperlink = .{ .uri = "https://www.google.com" },
    //             });

    //             var last_row = screen.view(0, screen.winsize.rows - 1, null, null, .allow_overflow);
    //             _ = try last_row.write(0, 0, "as", .{
    //                 .style = style_1,
    //                 .block = link,
    //             });
    //             _ = try last_row.write(0, 1, "test", .{});

    //             const style_2 = try screen.registerStyle(.{
    //                 .background = .rgb(34, 31, 48),
    //             });

    //             var last_row_2 = last_row.view(3, 0, null, null, .no_overflow);
    //             _ = try last_row_2.write(0, 0, "👨‍👩‍👧‍👦", .{
    //                 .style = style_2,
    //             });

    //             _ = try last_row.writeCell(4, 0, "t", .{
    //                 .style = style_2,
    //             });

    //             try screen.renderDirect(tty);
    //             try tty.flush();
    //         },
    //         else => {},
    //     }
    // }

    var manager = try zweave.Manager.init(allocator);
    global_tty = manager.tty;
    defer {
        manager.deinit();
        global_tty = null;
    }

    try manager.tty.enableAndResetAlternativeScreen();
    defer manager.tty.disableAlternativeScreen() catch {};
    try manager.tty.hideCursor();
    try manager.tty.flush();

    var block = Block{};
    const block_handle = try manager.tree.create(block.element());
    try manager.tree.addChildren(manager.root, &.{block_handle});

    try manager.renderNextFrame();

    while (true) {
        var event = manager.tty.nextEvent();
        defer event.deinit(allocator);

        switch (event) {
            .key_press => |key_press| {
                if (key_press.matches('c', .{ .ctrl = true })) {
                    break;
                }
            },
            else => {},
        }
    }

    return 0;
}

var global_tty: ?*zttio.Tty = null;

pub const panic = std.debug.FullPanic(testPanic);
pub fn testPanic(msg: []const u8, ret_addr: ?usize) noreturn {
    if (global_tty) |tty| {
        tty.revertTerminal();
    }

    std.debug.defaultPanic(msg, ret_addr);
}
