const std = @import("std");
const tracy = @import("tracy");

const Element = @import("../tree/element.zig");
const LayoutConstraints = @import("../tree/layout_constraints.zig");
const GraphemeGapBuffer = @import("../common/grapheme_gap_buffer.zig");
const LineIterator = @import("../common/line_iterator.zig");

const TextInput = @This();

allocator: std.mem.Allocator,
buf: GraphemeGapBuffer,

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
    return Element.Interface{
        .ptr = self,
        .vtable = &Element.Interface.VTable{
            .getLayoutConstraints = getLayoutConstraints,
            .draw = draw,

            .onEvent = onEvent,
        },
    };
}

pub fn getLayoutConstraints(self_ptr: *anyopaque, ctx: *const Element.GetLayoutConstraintsContext) Element.GetLayoutConstraintsError!LayoutConstraints {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[TextInput]: getLayoutConstraints",
        .src = @src(),
    });
    defer trace_zone.end();

    const self: *TextInput = @ptrCast(@alignCast(self_ptr));
    if (self.buf.len() == 0) {
        return .zero;
    }

    var height: u16 = 0;
    var max_width: u16 = 0;
    {
        var last_line: u16 = 0;

        {
            var line_iter = LineIterator.init(self.buf.firstHalf());
            while (line_iter.peek()) |line| : (line_iter.toss(line)) {
                height += 1;

                const width: u16 = @intCast(ctx.strWidth(line.bytes(&line_iter)));
                last_line = width;
                max_width = @max(max_width, width);
            }
        }

        {
            var line_iter = LineIterator.init(self.buf.secondHalf());
            var first_line = true;
            while (line_iter.peek()) |line| : (line_iter.toss(line)) {
                height += 1;

                if (first_line) {
                    first_line = false;
                    const width: u16 = @intCast(ctx.strWidth(line.bytes(&line_iter)));
                    max_width = @max(max_width, last_line + width);
                } else {
                    const width: u16 = @intCast(ctx.strWidth(line.bytes(&line_iter)));
                    max_width = @max(max_width, width);
                }
            }
        }
    }

    return LayoutConstraints{
        .height = .{ .fixed = @max(height, 1) },
        .width = .{ .fixed = @max(max_width, 1) },
    };
}

pub fn draw(self_ptr: *anyopaque, ctx: *const Element.DrawContext) Element.DrawError!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[TextInput]: draw",
        .src = @src(),
    });
    defer trace_zone.end();

    const self: *TextInput = @ptrCast(@alignCast(self_ptr));
    const view = &ctx.view;

    const end_pos = try view.writePos(0, 0, self.buf.firstHalf(), .{});
    _ = try view.writePos(end_pos.x, end_pos.y, self.buf.secondHalf(), .{});

    if (ctx.isFocused()) {
        view.setCursorPos(end_pos);
        view.setCursorShape(.blinking_bar);
        view.setCursorVisibility(true);
    }
}

pub fn onEvent(self_ptr: *anyopaque, ctx: *const Element.EventContext) Element.EventError!void {
    const self: *TextInput = @ptrCast(@alignCast(self_ptr));

    switch (ctx.event.*) {
        .key_press => |key_press| {
            if (key_press.matches(.left, .{})) {
                if (self.buf.canMoveGapLeft(1)) {
                    _ = self.buf.moveGapLeft(1);
                }
            } else if (key_press.matches(.right, .{})) {
                if (self.buf.canMoveGapRight(1)) {
                    _ = self.buf.moveGapRight(1);
                }
            } else if (key_press.matches(.backspace, .{})) {
                if (self.buf.canGrowGapLeft(1)) {
                    self.buf.growGapLeft(1);
                }
            } else if (key_press.text != .empty) {
                try self.buf.insertGrapheme(self.allocator, key_press.text.get());
            }
        },

        .paste => |paste| {
            try self.buf.insertGraphemeSlice(self.allocator, paste);
        },

        else => {},
    }
}
