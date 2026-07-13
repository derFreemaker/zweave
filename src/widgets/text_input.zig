const std = @import("std");

const tracy = @import("tracy");

const GraphemeGapBuffer = @import("../common/grapheme_gap_buffer.zig");
const LineIterator = @import("../common/line_iterator.zig");
const ScreenVec = @import("../screen/screen_vec.zig");
const Element = @import("../tree/element.zig");

const TextInput = @This();

allocator: std.mem.Allocator,
buf: GraphemeGapBuffer,
cached_size: ScreenVec = .zero,

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
        .getDebugStr = getDebugStr,

        .computeLayout = computeLayout,
        .draw = draw,

        .onEvent = onEvent,
    } };
}

fn getDebugStr(self_ctx: Element.SelfContext, ctx: *const Element.GetDebugStrContext) Element.GetDebugStrError![]const u8 {
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
        const size = ScreenVec{
            .x = 1,
            .y = 1,
        };
        self.cached_size = size;

        return size;
    }

    if (!self.cached_size.isNull()) {
        return self.cached_size;
    }

    var height: u16 = 1;
    var max_width: u16 = 0;
    {
        var last_line_width: u16 = 0;

        {
            var line_iter = LineIterator.init(self.buf.firstHalf());
            while (line_iter.peek()) |line| : (line_iter.toss(line)) {
                if (line.hasSeparator()) {
                    height += 1;
                }

                const bytes = line.bytes(&line_iter);
                const width: u16 = @intCast(ctx.strWidth(bytes));
                last_line_width = width;
                max_width = @max(max_width, width);

                if (line.isLast() and line.hasSeparator()) {
                    last_line_width = 0;
                }
            }
        }

        {
            var line_iter = LineIterator.init(self.buf.secondHalf());
            var empty_line = last_line_width != 0;
            while (line_iter.peek()) |line| : (line_iter.toss(line)) {
                if (line.hasSeparator()) {
                    height += 1;
                }

                const bytes = line.bytes(&line_iter);

                if (empty_line) {
                    empty_line = false;
                    const width: u16 = @intCast(ctx.strWidth(bytes));
                    max_width = @max(max_width, last_line_width + width);
                } else {
                    const width: u16 = @intCast(ctx.strWidth(bytes));
                    max_width = @max(max_width, width);
                }
            }
        }
    }

    // ensure we are never writing into the most right cell in the terminal,
    // since the cursor can not follow to the right side of the cell
    const size = ScreenVec{
        .x = @min(max_width, ctx.viewport_size.x -| 1),
        .y = height,
    };
    self.cached_size = size;

    return size;
}

fn draw(self_ctx: Element.SelfContext, ctx: *const Element.DrawContext) Element.DrawError!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[TextInput]: draw",
        .src = @src(),
    });
    defer trace_zone.end();

    const self = self_ctx.get(TextInput);

    if (ctx.view.size.isNull() or self.cached_size.isNull()) {
        if (ctx.isFocused(self_ctx.handle)) {
            if (ctx.view.setCursorPos(.zero)) {
                ctx.view.setCursorShape(.blinking_bar);
                ctx.view.setCursorVisibility(true);
            }
        }
        return;
    }

    const view = ctx.view;
    var view_writer = view.writer(&.{}, .{});
    const writer = &view_writer.interface;

    try writer.writeAll(self.buf.firstHalf());
    try writer.flush();

    if (ctx.isFocused(self_ctx.handle)) {
        if (view.setCursorPos(view_writer.pos)) {
            view.setCursorShape(.blinking_bar);
            view.setCursorVisibility(true);
        }
    }
    try writer.writeAll(self.buf.secondHalf());

    try writer.flush();
}

fn onEvent(self_ctx: Element.SelfContext, ctx: *const Element.OnEventContext) Element.OnEventError!void {
    const self = self_ctx.get(TextInput);

    const Key = @import("zttio").Key;
    const Mouse = @import("zttio").Mouse;
    onEvent: switch (ctx.event.*) {
        .key_press => |key_press| {
            if (!ctx.tree.isFocused(self_ctx.handle)) {
                return;
            }

            switch (key_press.switchable()) {
                Key.matches(.left, .{}) => {
                    ctx.consume();

                    if (self.buf.canMoveGapLeft(1)) {
                        _ = self.buf.moveGapLeft(1);

                        self.cached_size = .zero;
                    }
                },
                Key.matches(.right, .{}) => {
                    ctx.consume();

                    if (self.buf.canMoveGapRight(1)) {
                        _ = self.buf.moveGapRight(1);

                        self.cached_size = .zero;
                    }
                },
                Key.matches(.backspace, .{}) => {
                    ctx.consume();

                    if (self.buf.canGrowGapLeft(1)) {
                        self.buf.growGapLeft(1);

                        self.cached_size = .zero;
                    }
                },
                Key.matches(.enter, .{}) => {
                    ctx.consume();

                    try self.buf.insertGrapheme(self.allocator, "\n");

                    self.cached_size = .zero;
                },
                else => {
                    if (key_press.text != .empty) {
                        ctx.consume();

                        try self.buf.insertGrapheme(self.allocator, key_press.text.get());

                        self.cached_size = .zero;
                    }
                },
            }
        },

        .paste => |paste| {
            if (!ctx.tree.isFocused(self_ctx.handle)) {
                return;
            }

            ctx.consume();

            try self.buf.insertGraphemeSlice(self.allocator, paste);

            self.cached_size = .zero;
        },

        .mouse => |mouse| switch (mouse.switchable()) {
            Mouse.matches(.left, .press, .{}) => {
                if (ctx.mouse_rel_pos == null) {
                    break :onEvent;
                }

                ctx.consume();
                try ctx.tree.setFocus(self_ctx.handle);
            },
            else => {},
        },

        else => {},
    }
}
