const Block = struct {
    width: f32,
    height: f32,
    content_handle: zweave.StrHandle,
    styling: zweave.StylingHandle = .invalid,

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

        view.fill(0, 0, view.size.y, view.size.x, .{ .shared_long = self.content_handle }, .{
            .styling = self.styling,
        });

        _ = try view.write(10, 2, " hi Block here! ", .{
            .styling = self.styling,
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

    var adapter = try zttio.Adapters.NativeAdapter.init(allocator, init.io, .stdin(), .stdout());
    defer adapter.deinit(allocator);
    var tty = try zttio.Tty.init(
        allocator,
        event_allocator,
        adapter.adapter(),
        .{
            .caps = try zttio.TerminalCapabilities.query(init.io, init.environ_map, adapter.adapter(), .fromMilliseconds(100)),
        },
    );
    global_tty = &tty;
    defer {
        tty.deinit();
        global_tty = null;
    }

    const tty_winsize = tty.getWinsize();
    const screen_size = zweave.ScreenVec{
        .x = tty_winsize.cols,
        .y = tty_winsize.rows,
    };
    var engine = try zweave.Engine.init(allocator, tty.writer, tty.caps.unicode_width_method, screen_size);
    defer engine.deinit();

    try tty.enableAndResetAlternativeScreen();
    defer tty.disableAlternativeScreen() catch {};
    try tty.hideCursor();
    try tty.flush();

    const str2_handle = try engine.screen_store.addStr("F");
    defer engine.screen_store.removeStr(str2_handle);

    const str3_handle = try engine.screen_store.addStr("-");
    defer engine.screen_store.removeStr(str3_handle);

    const styling1_handle = try engine.screen_store.addStyling(zweave.Styling{
        .fg = .{ .c8 = .default },
        .bg = .{ .c8 = .green },
    });
    defer engine.screen_store.removeStyling(styling1_handle);

    var block = Block{
        .width = 0.5,
        .height = 0.3,
        .content_handle = str2_handle,
        .styling = styling1_handle,
    };
    const block_handle = try engine.tree.create(block.element());
    defer engine.tree.destroy(block_handle);

    const frame_label_handle = try engine.screen_store.addStr(" test input ");
    defer engine.screen_store.removeStr(frame_label_handle);

    var frame = zweave.Widgets.Frame{
        .border = .rounded,

        .label = frame_label_handle,
        .label_offset = 1,
    };
    const frame_handle = try engine.tree.create(frame.element());
    defer engine.tree.destroy(frame_handle);

    var screen = try zweave.Widgets.Screen.init(allocator, .{
        .store = &engine.screen_store,
        .size = .{ .x = 50, .y = 30 },
        .width_method = tty.caps.unicode_width_method,
    });
    defer screen.deinit(allocator);
    var screen_view_writer = screen.view.writer(&.{}, .{});
    const screen_writer = &screen_view_writer.interface;
    const screen_handle = try engine.tree.create(screen.element());
    defer engine.tree.destroy(screen_handle);

    var input = try zweave.Widgets.TextInput.init(allocator);
    defer input.deinit();
    const input_handle = try engine.tree.create(input.element());
    defer engine.tree.destroy(input_handle);

    engine.tree.addChildren(frame_handle, &.{input_handle});

    const frame_handle_2 = try engine.tree.create(frame.element());
    defer engine.tree.destroy(frame_handle_2);

    const input_handle_2 = try engine.tree.create(input.element());
    defer engine.tree.destroy(input_handle_2);

    engine.tree.addChildren(frame_handle_2, &.{input_handle_2});

    engine.tree.addChildren(engine.root, &.{ screen_handle, frame_handle, block_handle, frame_handle_2 });

    while (true) {
        var event = try tty.nextEvent();
        defer event.deinit(event_allocator);

        const trace_zone = tracy.Zone.begin(.{
            .name = "main_loop",
            .src = @src(),
        });
        defer trace_zone.end();

        var consumed = false;
        const Key = @import("zttio").Key;
        switch (event) {
            .key_press => |key_press| {
                consumed = true;

                switch (key_press.switchable()) {
                    Key.matches(.c, .{ .ctrl = true }) => {
                        break;
                    },
                    Key.matches(.f1, .{}) => {
                        engine.showStats(null);
                    },
                    Key.matches(.f2, .{}) => {
                        engine.showDebugTree(null);
                    },
                    Key.matches(.f3, .{}) => {
                        if (!engine.tree.isFocused(input_handle)) {
                            try engine.tree.setFocus(input_handle);
                        } else {
                            try engine.tree.removeFocus();
                        }
                    },
                    Key.matches(.enter, .{}) => {
                        try screen_writer.writeAll(input.buf.firstHalf());
                        try screen_writer.writeAll(input.buf.secondHalf());
                        try screen_writer.writeByte('\n');
                        try screen_writer.flush();

                        input.buf.clearRetainingCapacity();
                    },
                    else => {
                        consumed = false;
                    },
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

const std = @import("std");
const builtin = @import("builtin");

const tracy = @import("tracy");
const zweave = @import("zweave");
const zttio = zweave.zttio;
