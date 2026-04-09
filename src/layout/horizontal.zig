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

    //TODO: maybe abstract some logic into more easily understandable blocks for easier creation of other layout alogs
    var child_iter = ctx.tree.childs(handle);
    var available_height = ctx.available.y;
    var row_pos: u16 = 0;
    var max_row_width: u16 = 0;
    while (available_height > 0 and !child_iter.isEmpty()) {
        var available_width = ctx.available.x;
        var row_size: ScreenVec = .zero;
        while (available_width > 0 and !child_iter.isEmpty()) {
            const child_handle = child_iter.peek() orelse continue;
            const child = ctx.tree.get(child_handle);

            const child_available = ScreenVec{
                .x = if (row_size.x == 0) available_width else available_width - @min(available_width, opts.gap.x),
                .y = available_height,
            };
            const child_layout_ctx = ctx.child(child_available);
            const child_requested_size = try child.interface.computeLayout(&child_layout_ctx);

            const child_data = ctx.tree.getLayoutDataMut(child_handle);

            const total_child_width = if (row_size.x == 0) child_requested_size.x else child_requested_size.x + opts.gap.x;
            if (total_child_width <= available_width) {
                child_data.pos = ScreenVec{
                    .x = row_size.x,
                    .y = row_pos,
                };
                child_data.size = ScreenVec{
                    .x = child_requested_size.x,
                    .y = @min(child_requested_size.y, available_height),
                };

                available_width -= total_child_width;
                row_size.x += total_child_width;
                row_size.y = @max(row_size.y, child_requested_size.y);
            } else {
                available_width = 0;

                if (child_requested_size.x > ctx.available.x and row_size.x == 0) {
                    child_data.pos = ScreenVec{
                        .x = row_size.x,
                        .y = row_pos,
                    };
                    child_data.size = ScreenVec{
                        .x = ctx.available.x,
                        .y = child_requested_size.y,
                    };
                    row_size.x = ctx.available.x;
                    row_size.y = @min(child_requested_size.y, available_height);
                } else {
                    continue;
                }
            }

            child_iter.toss();
        }

        if (row_size.isNull()) {
            break;
        }

        max_row_width = @max(max_row_width, row_size.x);
        std.debug.assert(max_row_width <= ctx.available.x);

        const total_row_height = row_size.y + opts.gap.y;
        std.debug.assert(total_row_height <= available_height);
        available_height -= total_row_height;
        row_pos += total_row_height;
    }

    const total_size = ScreenVec{
        .x = max_row_width,
        .y = ctx.available.y - available_height,
    };
    std.debug.assert(total_size.inside(ctx.available));

    while (child_iter.peek()) |child_handle| : (child_iter.toss()) {
        const child_data = ctx.tree.getLayoutDataMut(child_handle);

        child_data.pos = total_size;
        child_data.size = .zero;
    }

    return total_size;
}
