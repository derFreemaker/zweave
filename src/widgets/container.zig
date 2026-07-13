const std = @import("std");
const tracy = @import("tracy");

const ScreenVec = @import("../screen/screen_vec.zig");
const Element = @import("../tree/element.zig");

const Container = @This();

gap: ScreenVec = .zero,

pub fn element(self: *Container) Element.Interface {
    return .{ .ptr = self, .vtable = &.{
        .getDebugStr = getDebugId,

        .computeLayout = computeLayout,
        .draw = draw,
    } };
}

fn getDebugId(self_ctx: Element.SelfContext, ctx: *const Element.GetDebugStrContext) Element.GetDebugStrError![]const u8 {
    return std.fmt.allocPrint(ctx.allocator, "<Container c:{d}>", .{ctx.tree.countChilds(self_ctx.handle)});
}

fn computeLayout(self_ctx: Element.SelfContext, ctx: *const Element.ComputeLayoutContext) Element.ComputeLayoutError!ScreenVec {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Container]: computeLayout",
        .src = @src(),
    });
    defer trace_zone.end();

    const self = self_ctx.get(Container);

    return @import("../layout/horizontal.zig").layout(self_ctx.handle, ctx, .{
        .gap = self.gap,
    });
}

fn draw(self_ctx: Element.SelfContext, ctx: *const Element.DrawContext) Element.DrawError!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Container]: draw",
        .src = @src(),
    });
    defer trace_zone.end();

    const view = &ctx.view;

    var child_iter = ctx.tree.childs(self_ctx.handle);
    while (child_iter.peek()) |child_handle| : (child_iter.toss()) {
        const child_layout_data = ctx.tree.getLayoutData(child_handle);
        const child_view = view.view(.{
            .pos = child_layout_data.pos,
            .size = child_layout_data.size,
        });
        const rel_pos: ?ScreenVec = blk: {
            var rel_pos = ctx.mouse_rel_pos orelse break :blk null;
            const child_rel_pos = rel_pos.subOverflow(child_layout_data.pos) catch break :blk null;
            if (child_rel_pos.x >= child_layout_data.size.x or child_rel_pos.y >= child_layout_data.size.y) {
                break :blk null;
            }
            break :blk child_rel_pos;
        };
        const child_ctx = ctx.child(child_view, rel_pos);

        const child = ctx.tree.get(child_handle);
        try child.interface.draw(&child_ctx);
    }
}
