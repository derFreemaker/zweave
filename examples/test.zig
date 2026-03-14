const std = @import("std");
const builtin = @import("builtin");

const zttio = @import("zttio");
const zweave = @import("zweave");

const Block = struct {
    width: f32,
    height: f32,
    content_handle: zweave.StrHandle,
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

        view.fill(ctx.screen_store, 0, 0, view.height, view.width, .{ .long_shared = self.content_handle }, .{
            .style = self.style,
        });

        _ = try view.write(10, 1, " hi Block here! ", .{
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

    var trace_event_allocator = zweave.Tracy.Allocator{
        .pool_name = "[terminal]: event_allocator",
        .parent = allocator,
    };
    const event_allocator = trace_event_allocator.allocator();

    var engine: zweave.Engine = undefined;
    try zweave.Engine.init_(&engine, allocator, event_allocator);
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

    // std.debug.print("{any}\n", .{engine.tty.caps});
    // std.debug.print("{any}\n", .{engine.renderer.next.width_method});
    // std.debug.print("👍 -> {d}\n", .{engine.renderer.next.strWidth("👍")});

    const str1_handle = try engine.screen_store.addStr("👍");
    defer engine.screen_store.removeStr(str1_handle);

    const str2_handle = try engine.screen_store.addStr("👨‍👩‍👧‍👦");
    defer engine.screen_store.removeStr(str2_handle);

    const str3_handle = try engine.screen_store.addStr("-");
    defer engine.screen_store.removeStr(str3_handle);

    const style1_handle = try engine.screen_store.addStyle(zweave.Style{
        .background = .{ .c8 = .blue },
        .underline = .{ .style = .dotted },
    });
    defer engine.screen_store.removeStyle(style1_handle);

    const style2_handle = try engine.screen_store.addStyle(zweave.Style{
        .background = .{ .c8 = .green },
        .attrs = .{ .italic = true },
    });
    defer engine.screen_store.removeStyle(style2_handle);

    var block1 = Block{
        .width = 0.3,
        .height = 0.2,
        .content_handle = str1_handle,
        .style = style1_handle,
    };
    const block1_handle = try engine.tree.create(block1.element());
    defer engine.tree.destroy(block1_handle);

    var block2 = Block{
        .width = 0.5,
        .height = 0.67,
        .content_handle = str2_handle,
        .style = style2_handle,
    };
    const block2_handle = try engine.tree.create(block2.element());
    defer engine.tree.destroy(block2_handle);

    var block3 = Block{
        .width = 0.1,
        .height = 0.05,
        .content_handle = str3_handle,
    };
    const block3_handle = try engine.tree.create(block3.element());
    defer engine.tree.destroy(block3_handle);

    var input = try zweave.Components.TextInput.init(allocator);
    defer input.deinit(allocator);
    const input_handle = try engine.tree.create(input.element());
    defer engine.tree.destroy(input_handle);

    try engine.tree.addChildren(engine.root, &.{ block1_handle, block2_handle, block3_handle, input_handle });

    while (true) {
        var event = engine.tty.nextEvent();
        defer event.deinit(event_allocator);

        const trace_zone = zweave.Tracy.Zone.begin(.{
            .name = "main_loop",
            .src = @src(),
        });
        defer trace_zone.end();

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
                } else if (key_press.matches(zttio.Key.backspace, .{})) {
                    input.buf.growGapLeft(1);
                } else if (key_press.matches(zttio.Key.enter, .{})) {
                    try input.buf.insertGrapheme(allocator, "\n");
                } else if (key_press.text != .empty) {
                    try input.buf.insertGrapheme(allocator, key_press.text.get());
                }
            },
            .paste => |paste| {
                try input.buf.insertGraphemeSlice(allocator, paste);
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

pub const tracy_impl = zweave.TracyImpl;
