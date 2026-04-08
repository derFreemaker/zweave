const std = @import("std");
const tracy = @import("tracy");

const ScreenVec = @import("../common/screen_vec.zig");
const Element = @import("../tree/element.zig");
const GraphemeGapBuffer = @import("../common/grapheme_gap_buffer.zig");
const LineIterator = @import("../common/line_iterator.zig");

const TextInput = @This();

allocator: std.mem.Allocator,
buf: GraphemeGapBuffer,
foo_: bool = false,

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!TextInput {
    return TextInput{
        .allocator = allocator,
        .buf = try GraphemeGapBuffer.initCapacity(allocator, 256),
    };
}

pub fn deinit(self: *TextInput) void {
    self.buf.deinit(self.allocator);
}

pub fn element(self: *TextInput) Element.Interface {
    return Element.Interface{ .ptr = self, .vtable = &Element.Interface.VTable{
        .getDebugStr = getDebugId,

        .computeLayout = computeLayout,
        .draw = draw,

        .onEvent = onEvent,
    } };
}

fn getDebugId(self_ctx: Element.SelfContext, ctx: *const Element.GetDebugIdContext) Element.GetDebugIdError![]const u8 {
    _ = self_ctx;
    _ = ctx;

    return "<TextInput>";
}

fn computeLayout(self_ctx: Element.SelfContext, ctx: *const Element.ComputeLayoutContext) Element.ComputeLayoutError!ScreenVec {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[TextInput]: computeLayout",
        .src = @src(),
    });
    defer trace_zone.end();

    const self = self_ctx.get(TextInput);
    if (self.buf.len() == 0) {
        return .{
            .x = 0,
            .y = 1,
        };
    }

    var height: u16 = 0;
    var max_width: u16 = 0;
    {
        var last_line: u16 = 0;

        {
            var line_iter = LineIterator.init(self.buf.firstHalf());
            while (line_iter.peek()) |line| : (line_iter.toss(line)) {
                height += 1;

                const bytes = line.bytes(&line_iter);
                const width: u16 = @intCast(ctx.strWidth(bytes));
                last_line = width;
                max_width = @max(max_width, width);

                if (line.isLast() and line.hasSeparator()) {
                    last_line = 0;
                }
            }
        }

        {
            var line_iter = LineIterator.init(self.buf.secondHalf());
            var first_line = last_line != 0;
            while (line_iter.peek()) |line| : (line_iter.toss(line)) {
                const bytes = line.bytes(&line_iter);

                if (first_line) {
                    first_line = false;
                    const width: u16 = @intCast(ctx.strWidth(bytes));
                    max_width = @max(max_width, last_line + width);
                } else {
                    height += 1;
                    const width: u16 = @intCast(ctx.strWidth(bytes));
                    max_width = @max(max_width, width);
                }
            }
        }
    }

    return ScreenVec{
        .x = max_width,
        .y = height,
    };
}

fn draw(self_ctx: Element.SelfContext, ctx: *const Element.DrawContext) Element.DrawError!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[TextInput]: draw",
        .src = @src(),
    });
    defer trace_zone.end();

    if (ctx.view.size.isNull()) {
        if (ctx.tree.isFocused(self_ctx.handle)) {
            ctx.view.setCursorPos(.zero);
            ctx.view.setCursorShape(.blinking_bar);
            ctx.view.setCursorVisibility(true);
        }
        return;
    }

    const self = self_ctx.get(TextInput);
    var view_writer = ctx.view.writer(&.{});
    const writer = &view_writer.writer;

    try writer.writeAll(self.buf.firstHalf());
    try writer.flush();

    if (ctx.tree.isFocused(self_ctx.handle) and
        (view_writer.pos.x <= ctx.view.size.x and
            view_writer.pos.y < ctx.view.size.y))
    {
        ctx.view.setCursorPos(view_writer.pos);
        ctx.view.setCursorShape(.blinking_bar);
        ctx.view.setCursorVisibility(true);
    }

    try writer.writeAll(self.buf.secondHalf());
    try writer.flush();
}

fn onEvent(self_ctx: Element.SelfContext, ctx: *Element.OnEventContext) Element.OnEventError!void {
    const self = self_ctx.get(TextInput);
    if (!ctx.tree.isFocused(self_ctx.handle)) return;

    switch (ctx.event.*) {
        .key_press => |key_press| {
            if (key_press.matches(.left, .{})) {
                ctx.consume();

                if (self.buf.canMoveGapLeft(1)) {
                    _ = self.buf.moveGapLeft(1);
                    ctx.tree.markDirty(self_ctx.handle);
                }
            } else if (key_press.matches(.right, .{})) {
                ctx.consume();

                if (self.buf.canMoveGapRight(1)) {
                    _ = self.buf.moveGapRight(1);
                    ctx.tree.markDirty(self_ctx.handle);
                }
            } else if (key_press.matches(.backspace, .{})) {
                ctx.consume();

                if (self.buf.canGrowGapLeft(1)) {
                    self.buf.growGapLeft(1);
                    ctx.tree.markDirty(self_ctx.handle);
                }
            } else if (key_press.text != .empty) {
                ctx.consume();

                try self.buf.insertGrapheme(self.allocator, key_press.text.get());
                ctx.tree.markDirty(self_ctx.handle);
            }
        },

        .paste => |paste| {
            ctx.consume();

            try self.buf.insertGraphemeSlice(self.allocator, paste);
            ctx.tree.markDirty(self_ctx.handle);
        },

        else => {},
    }
}
