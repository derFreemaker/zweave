const std = @import("std");

const ScreenVec = @import("../common/screen_vec.zig");
const Tree = @import("../tree/tree.zig");
const Element = @import("../tree/element.zig");

pub const Options = struct {
    gap: ScreenVec = .zero,
};

pub fn layout(handle: Element.Handle, ctx: *const Element.CalcLayoutContext, opts: Options) Element.CalcLayoutError!ScreenVec {
    if (!ctx.tree.get(handle).isDirty and !ctx.tree.get(handle).childIsDirty) {
        return ctx.tree.getLayoutData(handle).size;
    }

    var child_iter = ctx.tree.childs(handle);
    var max_row_height: u16 = 0;
    var pos: ScreenVec = .zero;
    var budget = ctx.available;
    var first: bool = true;
    while (child_iter.peek()) |child_handle| : (child_iter.toss()) {
        const child = ctx.tree.get(child_handle);

        const child_constraint = try child.interface.getLayoutConstraints(&ctx.toGetLayoutConstraintsContext());

        const child_data = ctx.tree.getLayoutDataMut(child_handle);
        if (child_constraint.isNull()) {
            child_data.size = .zero;
            continue;
        }

        if (!first) {
            pos.x += std.math.clamp(opts.gap.x, 0, budget.x);
            budget.x -= std.math.clamp(opts.gap.x, 0, budget.x);
            budget.y -= std.math.clamp(opts.gap.y, 0, budget.y);
        }
        first = false;
        child_data.pos = pos;

        const width = switch (child_constraint.width) {
            .fixed => |fixed| fixed,
            .percentage => |perc| @as(u16, @intFromFloat(@as(f32, @floatFromInt(ctx.available.x)) * perc)),
        };

        if (width > budget.x) {
            const next_row_y = max_row_height + opts.gap.y;
            pos.y = next_row_y;
            child_data.pos.x = 0;
            child_data.pos.y = next_row_y;
            max_row_height = 0;
            budget.y -= std.math.clamp(opts.gap.y, 0, budget.y);

            budget.x = ctx.available.x - @min(ctx.available.x, width);
            pos.x = width;
        } else {
            budget.x -= width;
            pos.x += width;
        }

        child_data.size.x = width;

        const height = switch (child_constraint.height) {
            .fixed => |fixed| fixed,
            .percentage => |perc| @as(u16, @intFromFloat(@as(f32, @floatFromInt(ctx.available.y)) * perc)),
        };

        if (height > budget.y) {
            budget.y = 0;
        } else {
            budget.y -= height;
        }

        child_data.size.y = height;
        max_row_height = @max(max_row_height, height);
    }

    return ctx.available;
}
