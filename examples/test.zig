const std = @import("std");
const builtin = @import("builtin");

const zttio = @import("zttio");
const zweave = @import("zweave");

const Block = struct {
    width: f32,
    height: f32,
    content: []const u8,
    style: zweave.SegmentHandle = .invalid,

    pub fn element(self: *Block) zweave.Element.Interface {
        return .{ .ptr = self, .vtable = &.{
            .getLayoutConstraints = getLayoutConstraints,
            .draw = draw,
        } };
    }

    pub fn getLayoutConstraints(ctx: *const zweave.Element.GetLayoutConstraintsContext) zweave.Element.GetLayoutConstraintsError!zweave.LayoutConstraints {
        const self: *Block = @ptrCast(@alignCast(ctx.self.interface.ptr));

        return zweave.LayoutConstraints{
            .height = .{ .percentage = self.height },
            .width = .{ .percentage = self.width },
        };
    }

    pub fn draw(ctx: *const zweave.Element.DrawContext) zweave.Element.DrawError!void {
        const self: *Block = @ptrCast(@alignCast(ctx.self.interface.ptr));
        const view = &ctx.view;

        for (0..view.height) |h| {
            for (0..view.width) |w| {
                _ = try view.writeCell(@intCast(w), @intCast(h), self.content, .{
                    .style = self.style,
                });
            }
        }

        _ = try view.write(0, 5, "hi Block here! ", .{
            .style = self.style,
        });
    }
};

pub fn main() !u8 {
    var gpa: std.heap.DebugAllocator(if (builtin.mode != .Debug) .{} else .{
        .retain_metadata = true,
        .never_unmap = true,
        .stack_trace_frames = 20,
    }) = .init;
    defer if (gpa.deinit() == .leak) @panic("memory leaks");
    const allocator = gpa.allocator();

    var engine: zweave.Engine = undefined;
    try zweave.Engine.init_(&engine, allocator);
    global_tty = engine.tty;
    defer {
        engine.tty.flush() catch {};
        engine.deinit();
        global_tty = null;
    }

    try engine.tty.enableAndResetAlternativeScreen();
    defer engine.tty.disableAlternativeScreen() catch {};
    try engine.tty.hideCursor();
    try engine.tty.flush();

    const style1_handle = try engine.screen_store.addStyle(zweave.Style{
        .background = .{ .c8 = .blue },
        .underline = .{ .style = .dotted },
    });
    defer engine.screen_store.removeStyle(style1_handle);

    var block1 = Block{
        .width = 0.3,
        .height = 0.2,
        .content = "#",
        .style = style1_handle,
    };
    const block1_handle = try engine.tree.create(block1.element());

    const style2_handle = try engine.screen_store.addStyle(zweave.Style{
        .background = .{ .c8 = .bright_red },
        .attrs = .{ .blink = true, .reverse = true },
    });
    defer engine.screen_store.removeStyle(style2_handle);

    var block2 = Block{
        .width = 0.5,
        .height = 0.67,
        .content = "+",
        .style = style2_handle,
    };
    const block2_handle = try engine.tree.create(block2.element());

    var block3 = Block{
        .width = 0.1,
        .height = 0.05,
        .content = "-",
    };
    const block3_handle = try engine.tree.create(block3.element());

    try engine.tree.addChildren(engine.root, &.{ block1_handle, block2_handle, block3_handle });

    while (true) {
        if (engine.tty.reader.queue.isEmpty()) {
            std.Thread.sleep(10 * std.time.ns_per_ms);
            continue;
        }

        var event = engine.tty.nextEvent();
        defer event.deinit(allocator);

        switch (event) {
            .key_press => |key_press| {
                if (key_press.matches('c', .{ .ctrl = true })) {
                    break;
                } else if (key_press.matches(zttio.Key.f1, .{})) {
                    engine.show_stats = !engine.show_stats;
                } else if (key_press.matches(zttio.Key.left, .{})) {
                    block1.width = std.math.clamp(block1.width - 0.05, 0, 0.75);
                } else if (key_press.matches(zttio.Key.right, .{})) {
                    block1.width = std.math.clamp(block1.width + 0.05, 0, 0.75);
                } else if (key_press.matches(zttio.Key.up, .{})) {
                    block1.height = std.math.clamp(block1.height - 0.05, 0, 0.6);
                } else if (key_press.matches(zttio.Key.down, .{})) {
                    block1.height = std.math.clamp(block1.height + 0.05, 0, 0.6);
                }
            },
            .winsize => |winsize| {
                try engine.resize(winsize);
            },
            .mouse, .mouse_leave => continue,
            else => {},
        }

        try engine.renderNextFrame();
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
