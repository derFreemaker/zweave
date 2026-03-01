const std = @import("std");
const builtin = @import("builtin");

const zttio = @import("zttio");
const zweave = @import("zweave");

const Block = struct {
    width: f32,
    height: f32,

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
        const view = &ctx.view;

        for (0..view.height) |h| {
            for (0..view.width) |w| {
                _ = try view.writeCell(@intCast(w), @intCast(h), "F", .{});
            }
        }
    }
};

pub fn main() !u8 {
    var gpa: std.heap.DebugAllocator(if (builtin.mode != .Debug) .{} else .{
        // .retain_metadata = true,
        // .never_unmap = true,
        .stack_trace_frames = 20,
    }) = .init;
    defer if (gpa.deinit() == .leak) @panic("memory leaks");
    const allocator = gpa.allocator();

    var manager: zweave.Manager = undefined;
    try zweave.Manager.init_(&manager, allocator);
    global_tty = manager.tty;
    defer {
        manager.tty.flush() catch {};
        manager.deinit();
        global_tty = null;
    }

    try manager.tty.enableAndResetAlternativeScreen();
    defer manager.tty.disableAlternativeScreen() catch {};
    try manager.tty.hideCursor();
    try manager.tty.flush();

    var block = Block{
        .width = 1,
        .height = 1,
    };
    const block_handle = try manager.tree.create(block.element());
    try manager.tree.addChildren(manager.root, &.{block_handle});

    while (true) {
        if (manager.tty.reader.queue.isEmpty()) {
            std.Thread.sleep(10 * std.time.ns_per_ms);
            continue;
        }

        var event = manager.tty.nextEvent();
        defer event.deinit(allocator);

        switch (event) {
            .key_press => |key_press| {
                if (key_press.matches('c', .{ .ctrl = true })) {
                    break;
                } else if (key_press.matches(zttio.Key.f1, .{})) {
                    manager.showStats = !manager.showStats;
                } else if (key_press.matches(zttio.Key.left, .{})) {
                    if (block.width != @as(f32, 0)) {
                        block.width -= 0.1;
                    }
                } else if (key_press.matches(zttio.Key.right, .{})) {
                    if (block.width != @as(f32, 1)) {
                        block.width += 0.1;
                    }
                } else if (key_press.matches(zttio.Key.up, .{})) {
                    if (block.height != @as(f32, 0)) {
                        block.height -= 0.1;
                    }
                } else if (key_press.matches(zttio.Key.down, .{})) {
                    if (block.height != @as(f32, 1)) {
                        block.height += 0.1;
                    }
                }
            },
            .winsize => |winsize| {
                try manager.renderer.resize(winsize);
            },
            else => {},
        }

        try manager.renderNextFrame();
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
