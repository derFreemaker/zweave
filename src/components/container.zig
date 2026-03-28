const std = @import("std");
const tracy = @import("tracy");

const ScreenVec = @import("../common/screen_vec.zig");
const Element = @import("../tree/element.zig");
const LayoutConstraints = @import("../layout/layout_constraints.zig");

const Container = @This();

pub fn init() Container {
    return Container{};
}

pub fn element(self: *Container) Element.Interface {
    return .{ .ptr = self, .vtable = &.{
        .getLayoutConstraints = getLayoutConstraints,
        .computeLayout = computeLayout,
        .draw = draw,
    } };
}

pub fn getLayoutConstraints(self_ptr: *anyopaque, ctx: *const Element.GetLayoutConstraintsContext) Element.GetLayoutConstraintsError!LayoutConstraints {
    _ = self_ptr;
    _ = ctx;

    return LayoutConstraints{
        .height = .{ .percentage = 1 },
        .width = .{ .percentage = 1 },
    };
}

pub fn computeLayout(self_ptr: *anyopaque, ctx: *const Element.CalcLayoutContext) Element.CalcLayoutError!ScreenVec {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Container]: computeLayout",
        .src = @src(),
    });
    defer trace_zone.end();

    _ = self_ptr;

    var child_iter = ctx.tree.childs(ctx.handle);
    var max_row_height: u16 = 0;
    var pos: ScreenVec = .zero;
    var budget = ctx.available;
    while (child_iter.peek()) |child_handle| : (child_iter.toss()) {
        const child = ctx.tree.get(child_handle);

        const child_constraint = try child.interface.getLayoutConstraints(&Element.GetLayoutConstraintsContext{
            .allocator = ctx.allocator,
            .tree = ctx.tree,
            .width_method = ctx.width_method,

            .handle = child_handle,
        });

        const child_data = ctx.tree.getLayoutDataMut(child_handle);
        child_data.pos = pos;

        if (child_constraint.isNull()) {
            continue;
        }

        const width = switch (child_constraint.width) {
            .fixed => |fixed| fixed,
            .percentage => |perc| @as(u16, @intFromFloat(@as(f32, @floatFromInt(ctx.available.x)) * perc)),
        };

        if (width > budget.x) {
            pos.y = max_row_height;
            child_data.pos.x = 0;
            child_data.pos.y = max_row_height;
            max_row_height = 0;

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

pub fn draw(self_ptr: *anyopaque, ctx: *const Element.DrawContext) Element.DrawError!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Container]: draw",
        .src = @src(),
    });
    defer trace_zone.end();

    _ = self_ptr;

    const view = &ctx.view;

    var child_iter = ctx.tree.childs(ctx.handle);
    while (child_iter.peek()) |child_handle| : (child_iter.toss()) {
        const child = ctx.tree.get(child_handle);
        const child_layout_data = ctx.tree.getLayoutData(child_handle);

        const child_view = view.view(.{
            .col = child_layout_data.pos.x,
            .row = child_layout_data.pos.y,
            .width = child_layout_data.size.x,
            .height = child_layout_data.size.y,
        });

        try child.interface.draw(&Element.DrawContext{
            .tree = ctx.tree,

            .handle = child_handle,

            .view = child_view,
            .screen_store = ctx.screen_store,
        });
    }
}
