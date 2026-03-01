const std = @import("std");

const Element = @import("../element.zig");
const LayoutConstraints = @import("../layout_constraints.zig");

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

    var budget = ctx.available;
    var childs_data = try ctx.allocator.alloc(ChildData, childs.len);
    defer ctx.allocator.free(childs_data);
    for (child_constraints, 0..) |child_constraint, i| {
        const child_data: *ChildData = &childs_data[i];

        switch (child_constraint.width) {
            .fixed => |fixed| {
                if (budget.x > fixed) {
                    budget.x -= fixed;
                } else {
                    child_data.is_overflowing = true;
                    budget.x = 0;
                }

                child_data.size.x += fixed;
            },
            .percentage => |perc| {
                const width: u16 = @intFromFloat(@as(f32, @floatFromInt(ctx.available.x)) * perc);

                if (width > budget.x) {
                    child_data.is_overflowing = true;
                    budget.x = 0;
                } else {
                    budget.x -= width;
                }
            },
        }

        switch (child_constraint.height) {
            .fixed => |fixed| {
                if (budget.y > fixed) {
                    budget.y -= fixed;
                } else {
                    child_data.is_overflowing = true;
                    budget.y = 0;
                }

                child_data.size.y += fixed;
            },
            .percentage => |perc| {
                const height: u16 = @intFromFloat(@as(f32, @floatFromInt(ctx.available.y)) * perc);

                if (height > budget.y) {
                    child_data.is_overflowing = true;
                    budget.y = 0;
                } else {
                    budget.y -= height;
                }
            },
        }
    }

    return .{ .x = ctx.available.x - budget.x, .y = ctx.available.y - budget.y };
}

const ChildData = struct {
    // has_range: bool = false,
    size: Element.SmallVec2 = .{ .x = 0, .y = 0 },
    is_overflowing: bool = false,
};

pub fn draw(ctx: *const Element.DrawContext) Element.DrawError!void {
    const view = &ctx.view;

    for (0..view.height) |h| {
        for (0..view.width) |w| {
            _ = try view.writeCell(@intCast(w), @intCast(h), "F", .{});
        }
    }
}
