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
    // return try LayoutConstraints.computeLayoutConstraint(ctx.allocator, ctx.tree, ctx.self.children.items, .{});

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
    return try LayoutConstraints.computeLayout(
        ctx.allocator,
        ctx.tree,
        ctx.self.children.items,
        .{
            .available = ctx.available,
        },
    );
}

pub fn draw(ctx: *const Element.DrawContext) Element.DrawError!void {
    const view = &ctx.view;

    for (0..view.height) |h| {
        for (0..view.width) |w| {
            _ = try view.writeCell(@intCast(w), @intCast(h), "F", .{});
        }
    }
}
