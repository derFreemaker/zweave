const std = @import("std");
const tracy = @import("tracy");

const Element = @import("../tree/element.zig");
const LayoutConstraints = @import("../tree/layout_constraints.zig");
const GraphemeGapBuffer = @import("../common/grapheme_gap_buffer.zig");

const TextInput = @This();

buf: GraphemeGapBuffer,

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!TextInput {
    return TextInput{
        .buf = try GraphemeGapBuffer.initCapacity(allocator, 256),
    };
}

pub fn deinit(self: *TextInput, allocator: std.mem.Allocator) void {
    self.buf.deinit(allocator);
}

pub fn element(self: *TextInput) Element.Interface {
    return Element.Interface{
        .ptr = self,
        .vtable = &Element.Interface.VTable{
            .getLayoutConstraints = getLayoutConstraints,
            .draw = draw,
        },
    };
}

pub fn getLayoutConstraints(ctx: *const Element.GetLayoutConstraintsContext) Element.GetLayoutConstraintsError!LayoutConstraints {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[TextInput]: getLayoutConstraints",
        .src = @src(),
    });
    defer trace_zone.end();

    const self = ctx.getSelf(TextInput);
    if (self.buf.len() == 0) {
        return .zero;
    }

    const height = std.mem.count(u8, self.buf.firstHalf(), "\n") + std.mem.count(u8, self.buf.secondHalf(), "\n") + 1;
    var max_width: u16 = 0;
    var last_line: u16 = 0;

    if (self.buf.firstHalf().len > 0) {
        var line_iter = std.mem.splitScalar(u8, self.buf.firstHalf(), '\n');
        while (line_iter.next()) |line| {
            last_line = @as(u16, @intCast(ctx.strWidth(line)));
            max_width = @max(max_width, last_line);
        }
    }

    if (self.buf.secondHalf().len > 0) {
        var first_line = true;
        var line_iter = std.mem.splitScalar(u8, self.buf.secondHalf(), '\n');
        while (line_iter.next()) |line| {
            if (first_line) {
                first_line = false;
                max_width = @max(max_width, last_line + @as(u16, @intCast(ctx.strWidth(line))));
                continue;
            }

            last_line = @as(u16, @intCast(ctx.strWidth(line)));
            max_width = @max(max_width, last_line);
        }
    }

    return LayoutConstraints{
        .height = .{ .fixed = @intCast(height) },
        .width = .{ .fixed = max_width },
    };
}

pub fn draw(ctx: *const Element.DrawContext) Element.DrawError!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[TextInput]: draw",
        .src = @src(),
    });
    defer trace_zone.end();

    const self = ctx.getSelf(TextInput);
    const view = &ctx.view;

    const end_pos = try view.writePos(0, 0, self.buf.firstHalf(), .{});
    _ = try view.writePos(end_pos.row, end_pos.col, self.buf.secondHalf(), .{});
}
