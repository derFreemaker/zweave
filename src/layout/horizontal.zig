const std = @import("std");

const ScreenVec = @import("../common/screen_vec.zig");
const Tree = @import("../tree/tree.zig");
const Element = @import("../tree/element.zig");

pub const Options = struct {
    gap: ScreenVec = .zero,
};

pub fn layout(handle: Element.Handle, ctx: *const Element.ComputeLayoutContext, opts: Options) Element.ComputeLayoutError!ScreenVec {
    if (!ctx.tree.get(handle).isDirty and !ctx.tree.get(handle).childIsDirty) {
        return ctx.tree.getLayoutData(handle).size;
    }

    // var child_iter = ctx.tree.childs(handle);
    // var pos: ScreenVec = .zero;
    // var max_width: u16 = 0;
    // var budget = ctx.available;
    // while (child_iter.peek()) |child_handle| : (child_iter.toss()) {
    //     const child = ctx.tree.get(child_handle);

    //     const child_constraint = try child.interface.getLayoutConstraints(&ctx.toGetLayoutConstraintsContext());

    //     const child_data = ctx.tree.getLayoutDataMut(child_handle);

    //     if (pos.x != 0) {
    //         pos.x += std.math.clamp(opts.gap.x, 0, budget.x);
    //     }
    // }

    var child_iter = ctx.tree.childs(handle);
    var max_row_height: u16 = 0;
    var max_width: u16 = 0;
    var pos: ScreenVec = .zero;
    var budget = ctx.available;
    var first: bool = true;
    var first_on_row: bool = true;
    while (child_iter.peek()) |child_handle| : (child_iter.toss()) {
        const child = ctx.tree.get(child_handle);

        const child_layout_ctx = ctx.child(budget);
        const child_requested_size = try child.interface.computeLayout(&child_layout_ctx);

        const child_data = ctx.tree.getLayoutDataMut(child_handle);

        if (!first_on_row) {
            pos.x += std.math.clamp(opts.gap.x, 0, budget.x);
            budget.x -= std.math.clamp(opts.gap.x, 0, budget.x);
        }
        first_on_row = false;
        if (!first) {
            budget.y -= std.math.clamp(opts.gap.y, 0, budget.y);
        }
        first = false;
        child_data.pos = pos;

        if (child_requested_size.isNull()) {
            child_data.size = .zero;
            continue;
        }

        const width = child_requested_size.x;

        if (width > budget.x) {
            child_data.size.x = @min(width, ctx.available.x);

            const next_row_y = max_row_height + opts.gap.y;
            child_data.pos.x = 0;
            child_data.pos.y = next_row_y;
            max_row_height = 0;
            budget.y -= std.math.clamp(opts.gap.y, 0, budget.y);

            budget.x = ctx.available.x - @min(ctx.available.x, width);
            first_on_row = true;
            pos = .{
                .x = width,
                .y = next_row_y,
            };

            max_width = ctx.available.x;
        } else {
            child_data.size.x = width;

            budget.x -= width;
            pos.x += width;

            max_width += width;
        }

        const height = child_requested_size.y;

        if (height > budget.y) {
            child_data.size.y = budget.y;

            budget.y = 0;
        } else {
            child_data.size.y = height;

            budget.y -= height;
        }

        max_row_height = @max(max_row_height, height);
    }

    return ScreenVec{
        .x = max_width,
        .y = ctx.available.y - budget.y,
    };
}
