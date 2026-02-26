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
        .height = .{ .range = .{
            .min = 0,
        } },
        .width = .{ .range = .{
            .min = 0,
        } },
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
    var child_sizes = try ctx.allocator.alloc(Element.SmallVec2, childs.len);
    defer ctx.allocator.free(child_sizes);
    for (child_constraints, 0..) |child_constraint, i| {
        const child_size = &child_sizes[i];

        switch (child_constraint.width) {
            .fixed => |fixed| {
                budget.x -= fixed;
                child_size.x += fixed;
            },
        }

        switch (child_constraint.height) {
            .fixed => |fixed| {
                budget.y -= fixed;
                child_size.y += fixed;
            },
        }
    }
}

pub fn draw(ctx: *const Element.DrawContext) Element.DrawError!void {
    const view = &ctx.view;

    for (0..view.height) |h| {
        for (0..view.width) |w| {
            _ = try view.writeCell(@intCast(w), @intCast(h), "F", .{});
        }
    }
}
