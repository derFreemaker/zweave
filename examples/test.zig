const std = @import("std");
const builtin = @import("builtin");
const tracy = @import("tracy");

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

    pub fn getLayoutConstraints(self_ptr: *anyopaque, ctx: *const zweave.Element.GetLayoutConstraintsContext) zweave.Element.GetLayoutConstraintsError!zweave.LayoutConstraints {
        const self: *Block = @ptrCast(@alignCast(self_ptr));
        _ = ctx;

        return zweave.LayoutConstraints{
            .height = .{ .percentage = self.height },
            .width = .{ .percentage = self.width },
        };
    }

    pub fn draw(self_ptr: *anyopaque, ctx: *const zweave.Element.DrawContext) zweave.Element.DrawError!void {
        const self: *Block = @ptrCast(@alignCast(self_ptr));
        const view = &ctx.view;

        view.fill(ctx.screen_store, 0, 0, view.size.y, view.size.x, .{ .long_shared = self.content_handle }, .{
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

    var trace_event_allocator = tracy.Allocator{
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

    var block2 = Block{
        .width = 0.5,
        .height = 0.67,
        .content_handle = str2_handle,
        .style = style2_handle,
    };
    const block2_handle = try engine.tree.create(block2.element());
    defer engine.tree.destroy(block2_handle);

    var screen = try zweave.Components.Screen.init(allocator, .{
        .size = .{ .x = 60, .y = 30 },
        .width_method = engine.tty.caps.unicode_width_method,
    });
    defer screen.deinit(allocator);
    const screen_handle = try engine.tree.create(screen.element());
    defer engine.tree.destroy(screen_handle);
    var screen_view_writer = screen.view.writer(&.{});
    const screen_writer = &screen_view_writer.interface;

    var input = try zweave.Components.TextInput.init(allocator);
    defer input.deinit();
    const input_handle = try engine.tree.create(input.element());
    defer engine.tree.destroy(input_handle);

    try engine.tree.addChildren(engine.root, &.{ screen_handle, block2_handle, input_handle });

    while (true) {
        var event = engine.tty.nextEvent();
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
                if (key_press.matches(.from('c'), .{ .ctrl = true })) {
                    consumed = true;
                    break;
                } else if (key_press.matches(.f1, .{})) {
                    consumed = true;
                    engine.show_stats = !engine.show_stats;
                } else if (key_press.matches(.f2, .{})) {
                    consumed = true;
                    if (engine.tree.focused_element.eql(input_handle)) {
                        engine.tree.removeFocus();
                    } else {
                        try engine.tree.setFocus(input_handle);
                    }
                } else if (key_press.matches(.enter, .{})) {
                    consumed = true;
                    if (engine.tree.isFocused(input_handle)) {
                        try screen_writer.writeAll(input.buf.firstHalf());
                        try screen_writer.writeAll(input.buf.secondHalf());
                        try screen_writer.writeByte('\n');
                        try screen_writer.flush();

                        input.buf.clearRetainingCapacity();
                    }
                }
            },
            .winsize => |winsize| {
                try engine.resize(winsize);
            },
            else => {},
        }

        if (!consumed) {
            if (zweave.Event.from(event)) |zweave_event| {
                try engine.dispatchEventToFocusedElement(zweave_event);
            }
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

pub const tracy_impl = @import("tracy_impl");
pub const tracy_options: tracy.Options = .{
    .on_demand = false,
    .no_broadcast = false,
    .only_localhost = false,
    .only_ipv4 = false,
    .delayed_init = false,
    .manual_lifetime = false,
    .verbose = true,
    .data_port = null,
    .broadcast_port = null,
    .default_callstack_depth = 20,
};
