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

    const height = std.mem.count(u8, self.buf.firstHalf(), "\n") + std.mem.count(u8, self.buf.secondHalf(), "\n") + 1;
    var max_width: u16 = 0;

    {
        var line_iter = std.mem.splitScalar(u8, self.buf.firstHalf(), '\n');
        while (line_iter.next()) |line| {
            max_width = @max(max_width, @as(u16, @intCast(ctx.strWidth(line))));
        }
    }

    {
        var line_iter = std.mem.splitScalar(u8, self.buf.secondHalf(), '\n');
        while (line_iter.next()) |line| {
            max_width = @max(max_width, @as(u16, @intCast(ctx.strWidth(line))));
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

    var end_pos = try view.write(0, 0, self.buf.firstHalf(), .{});
    end_pos = try view.write(end_pos.row, end_pos.col, self.buf.secondHalf(), .{});
}
