const std = @import("std");
const tracy = @import("tracy");

const Element = @import("../tree/element.zig");
const LayoutConstraints = @import("../tree/layout_constraints.zig");

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

pub fn getLayoutConstraints(ctx: *const Element.GetLayoutConstraintsContext) Element.GetLayoutConstraintsError!LayoutConstraints {
    _ = ctx;

    return LayoutConstraints{
        .height = .{ .percentage = 1 },
        .width = .{ .percentage = 1 },
    };
}

pub fn computeLayout(ctx: *const Element.CalcLayoutContext) Element.CalcLayoutError!Element.SmallVec2 {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[container]: layout",
        .src = @src(),
    });
    defer trace_zone.end();

    const childs = ctx.self.children.items;

    var child_constraints = try ctx.allocator.alloc(LayoutConstraints, childs.len);
    defer ctx.allocator.free(child_constraints);
    for (childs, 0..) |child_handle, i| {
        const child_element = ctx.tree.get(child_handle);

        child_constraints[i] = try child_element.interface.vtable.getLayoutConstraints(&Element.GetLayoutConstraintsContext{
            .allocator = ctx.allocator,
            .tree = ctx.tree,

            .self = child_element,
            .self_handle = child_handle,
        });
    }

    var max_row_height: u16 = 0;
    var pos: Element.SmallVec2 = .{ .x = 0, .y = 0 };
    var budget = ctx.available;
    for (child_constraints, 0..) |child_constraint, i| {
        const child_data = ctx.tree.getLayoutDataMut(childs[i]);
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

            budget.x = ctx.available.x - width;
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

pub fn draw(ctx: *const Element.DrawContext) Element.DrawError!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[container]: draw",
        .src = @src(),
    });
    defer trace_zone.end();

    const view = &ctx.view;

    const childs = ctx.self.children.items;
    for (childs) |child_handle| {
        const child = ctx.tree.get(child_handle);
        const child_layout_data = ctx.tree.getLayoutData(child_handle);

        const child_view = view.view(.{
            .col = child_layout_data.pos.x,
            .row = child_layout_data.pos.y,
            .width = child_layout_data.size.x,
            .height = child_layout_data.size.y,
        });

        try child.interface.vtable.draw(&Element.DrawContext{
            .tree = ctx.tree,

            .self = child,
            .self_handle = child_handle,

            .view = child_view,
            .screen_store = ctx.screen_store,
        });
    }
}
