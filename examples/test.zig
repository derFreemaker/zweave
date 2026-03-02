const std = @import("std");
const builtin = @import("builtin");

const zttio = @import("zttio");
const zweave = @import("zweave");

const Block = struct {
    width: f32,
    height: f32,
    content: []const u8,

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
                _ = try view.writeCell(@intCast(w), @intCast(h), self.content, .{});
            }
        }

        _ = try view.write(0, 5, "hi Block here! ", .{});
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
        .width = 0.3,
        .height = 0.2,
        .content = "#",
    };
    const block_handle = try manager.tree.create(block.element());

    var block2 = Block{
        .width = 0.5,
        .height = 0.67,
        .content = "+",
    };
    const block2_handle = try manager.tree.create(block2.element());

    var block3 = Block{
        .width = 0.1,
        .height = 0.05,
        .content = "-",
    };
    const block3_handle = try manager.tree.create(block3.element());

    try manager.tree.addChildren(manager.root, &.{ block_handle, block2_handle, block3_handle });

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
                    block.width = std.math.clamp(block.width - 0.05, 0, 0.75);
                } else if (key_press.matches(zttio.Key.right, .{})) {
                    block.width = std.math.clamp(block.width + 0.05, 0, 0.75);
                } else if (key_press.matches(zttio.Key.up, .{})) {
                    block.height = std.math.clamp(block.height - 0.05, 0, 0.6);
                } else if (key_press.matches(zttio.Key.down, .{})) {
                    block.height = std.math.clamp(block.height + 0.05, 0, 0.6);
                }
            },
            .winsize => |winsize| {
                try manager.renderer.resize(winsize);
            },
            .mouse, .mouse_leave => continue,
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
