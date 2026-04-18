const std = @import("std");
const builtin = @import("builtin");
const tracy = @import("tracy");

const zttio = @import("zttio");
const zweave = @import("zweave");

const Block = struct {
    width: f32,
    height: f32,
    content_handle: zweave.StrHandle,
    style: zweave.StyleHandle = .invalid,

    pub fn element(self: *Block) zweave.Element.Interface {
        return .{ .ptr = self, .vtable = &.{
            .draw = draw,

            .computeLayout = computeLayout,
            .onEvent = null,
        } };
    }

    fn computeLayout(self_ctx: zweave.Element.SelfContext, ctx: *const zweave.Element.ComputeLayoutContext) zweave.Element.ComputeLayoutError!zweave.ScreenVec {
        const self = self_ctx.get(Block);

        return ctx.viewport_size.scale(self.width, self.height);
    }

    fn draw(self_ctx: zweave.Element.SelfContext, ctx: *const zweave.Element.DrawContext) zweave.Element.DrawError!void {
        const self = self_ctx.get(Block);
        const view = &ctx.view;

        view.fill(ctx.screen_store, 0, 0, view.size.y, view.size.x, .{ .long_shared = self.content_handle }, .{
            .style = self.style,
        });

        _ = try view.write(10, 2, "hi Block here!", .{
            .style = self.style,
        });
    }
};

pub fn main(init: std.process.Init) !u8 {
    var gpa: std.heap.DebugAllocator(if (builtin.mode != .Debug) .{} else .{
        .retain_metadata = true,
        .never_unmap = true,
        .stack_trace_frames = 20,
    }) = .init;
    defer if (gpa.deinit() == .leak) @panic("memory leaks");
    const allocator = gpa.allocator();

    var trace_event_allocator = tracy.Allocator{
        .pool_name = "[terminal]: event_allocator",
        .parent = allocator,
    };
    const event_allocator = trace_event_allocator.allocator();

    var engine = try zweave.Engine.init(allocator, event_allocator, init.io, init.environ_map);
    global_tty = &engine.tty;
    defer {
        engine.tty.flush() catch {};
        global_tty = null;
        engine.deinit();
    }

    try engine.tty.enableAndResetAlternativeScreen();
    defer engine.tty.disableAlternativeScreen() catch {};
    try engine.tty.hideCursor();
    try engine.tty.flush();

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
    });
    defer engine.screen_store.removeStyle(style2_handle);

    var block = Block{
        .width = 0.5,
        .height = 0.3,
        .content_handle = str2_handle,
        .style = style2_handle,
    };
    const block_handle = try engine.tree.create(block.element());
    defer engine.tree.destroy(block_handle);

    const frame_label_handle = try engine.screen_store.addStr(zweave.BoxDrawing.DoubleVerticalAndLeft ++ " test input " ++ zweave.BoxDrawing.DoubleVerticalAndRight);
    defer engine.screen_store.removeStr(frame_label_handle);

    var frame = zweave.Widgets.Frame{
        .border = .double,

        .label = frame_label_handle,
        .label_col = 1,
    };
    const frame_handle = try engine.tree.create(frame.element());
    defer engine.tree.destroy(frame_handle);

    var screen = try zweave.Widgets.Screen.init(allocator, .{
        .size = .{ .x = 50, .y = 30 },
        .width_method = engine.tty.caps.unicode_width_method,
    });
    defer screen.deinit(allocator);
    var screen_view_writer = screen.view.writer(&.{});
    const screen_writer = &screen_view_writer.writer;
    const screen_handle = try engine.tree.create(screen.element());
    defer engine.tree.destroy(screen_handle);

    var input = try zweave.Widgets.TextInput.init(allocator);
    defer input.deinit();
    const input_handle = try engine.tree.create(input.element());
    defer engine.tree.destroy(input_handle);

    engine.tree.addChildren(frame_handle, &.{input_handle});

    engine.tree.addChildren(engine.root, &.{ screen_handle, frame_handle, block_handle });

    while (true) {
        var event = try engine.tty.nextEvent();
        defer event.deinit(event_allocator);

        const trace_zone = tracy.Zone.begin(.{
            .name = "main_loop",
            .src = @src(),
            .callstack_depth = 62,
        });
        defer trace_zone.end();

        var consumed = false;
        switch (event) {
            .key_press => |key_press| {
                consumed = true;

                if (key_press.matches(.from('c'), .{ .ctrl = true })) {
                    break;
                } else if (key_press.matches(.f1, .{})) {
                    engine.showStats(null);
                } else if (key_press.matches(.f2, .{})) {
                    engine.showDebugTree(null);
                } else if (key_press.matches(.f3, .{})) {
                    if (!engine.tree.isFocused(input_handle)) {
                        try engine.tree.setFocus(input_handle);
                    } else {
                        engine.tree.removeFocus();
                    }
                } else if (key_press.matchExact(.enter, .{ .shift = true })) {
                    if (engine.tree.isFocused(input_handle)) {
                        try screen_writer.writeAll(input.buf.firstHalf());
                        try screen_writer.writeAll(input.buf.secondHalf());
                        try screen_writer.writeByte('\n');
                        try screen_writer.flush();

                        input.buf.clearRetainingCapacity();
                    }
                } else {
                    consumed = false;
                }
            },
            .winsize => |winsize| {
                try engine.resize(.{ .x = winsize.cols, .y = winsize.rows });
            },
            else => {},
        }

        if (!consumed) {
            if (zweave.Event.from(event)) |zweave_event| {
                try engine.dispatchEvent(&zweave_event);
            }
        }

        try engine.renderNextFrame(init.io);
    }

    return 0;
}

var global_tty: ?*zttio.Tty = null;

pub const panic = std.debug.FullPanic(testPanic);
pub fn testPanic(msg: []const u8, ret_addr: ?usize) noreturn {
    if (global_tty) |tty| {
        tty.deinit();
    }

    std.debug.defaultPanic(msg, ret_addr);
}

pub const tracy_impl = @import("tracy_impl");
