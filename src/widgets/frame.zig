const std = @import("std");

const Cell = @import("../screen/cell.zig");
const ScreenStore = @import("../screen/screen_store.zig");
const ScreenVec = @import("../screen/screen_vec.zig");
const Styling = @import("../screen/styling.zig").Styling;
const BoxDrawing = @import("../symbols/box_drawing.zig");
const Element = @import("../tree/element.zig");

const Frame = @This();

padding: Padding = .{ .sides = .{
    .left = 1,
    .right = 1,
} },
border: Border = .none,
border_style: BorderStyle = .{},

label_offset: u16 = 0,
label: ScreenStore.StrHandle = .invalid,

pub fn element(self: *Frame) Element.Interface {
    return Element.Interface{ .ptr = self, .vtable = &Element.Interface.VTable{
        .getDebugStr = getDebugStr,

        .computeLayout = computeLayout,
        .draw = draw,

        .onEvent = onEvent,
    } };
}

fn getDebugStr(self_ctx: Element.SelfContext, ctx: *const Element.GetDebugStrContext) Element.GetDebugStrError![]const u8 {
    _ = self_ctx;
    _ = ctx;

    return "<Frame>";
}

fn computeLayout(self_ctx: Element.SelfContext, ctx: *const Element.ComputeLayoutContext) Element.ComputeLayoutError!ScreenVec {
    const self = self_ctx.get(Frame);

    const border = blk: {
        var border = switch (self.border) {
            .none => ScreenVec.zero,
            .single_cell => ScreenVec{ .x = 2, .y = 2 },
        };
        if (self.label.maybeValid()) |_| {
            border = border.max(ScreenVec{ .x = 0, .y = 1 });
        }
        break :blk border;
    };

    const padding = switch (self.padding) {
        .none => ScreenVec.zero,
        .all => |v| ScreenVec{ .x = v * 2, .y = v * 2 },
        .sides => |sides| ScreenVec{ .x = sides.left + sides.right, .y = sides.top + sides.bottom },
    };

    const label_width: u16 = if (self.label.maybeValid()) |label_handle|
        @intCast(self.label_offset + ctx.strWidth(ctx.screen_store.getStr(label_handle).*))
    else
        0;

    const min_size: ScreenVec = blk: {
        break :blk border.add(padding).add(ScreenVec{ .x = label_width, .y = 0 });
    };

    const self_element = ctx.tree.get(self_ctx.handle);
    const child_handle = self_element.first_child.maybeValid() orelse return min_size;

    const child = ctx.tree.get(child_handle);

    const child_available = ctx.available.sub(padding).sub(border);
    const child_ctx = ctx.child(child_available);
    const child_size = (try child.interface.computeLayout(&child_ctx)).max(ScreenVec{ .x = label_width -| padding.x, .y = 0 });

    const padding_top_left = switch (self.padding) {
        .none => ScreenVec.zero,
        .all => |v| ScreenVec{ .x = v, .y = v },
        .sides => |sides| ScreenVec{
            .x = sides.left,
            .y = sides.top,
        },
    };

    var border_top_left = switch (self.border) {
        .none => ScreenVec.zero,
        .single_cell => ScreenVec{ .x = 1, .y = 1 },
    };
    if (self.label.maybeValid()) |_| {
        border_top_left = border_top_left.max(ScreenVec{ .x = 0, .y = 1 });
    }

    const child_data = ctx.tree.getLayoutData(child_handle);
    child_data.pos = padding_top_left.add(border_top_left);
    child_data.size = child_size;

    var requested_size = child_size.add(padding).add(border);
    if (self.label.maybeValid()) |label_handle| {
        const width_border: u16 = switch (self.border) {
            .none => 0,
            .single_cell => 2,
        };

        const width_label = ctx.strWidth(ctx.screen_store.getStr(label_handle).*);

        requested_size = requested_size.max(ScreenVec{ .x = @intCast(self.label_offset + width_label + width_border), .y = 1 });
    }

    return requested_size;
}

fn draw(self_ctx: Element.SelfContext, ctx: *const Element.DrawContext) Element.DrawError!void {
    const self = self_ctx.get(Frame);

    draw_frame: switch (self.border) {
        .none => {
            if (self.label.maybeValid()) |label_handle| {
                _ = try ctx.view.write(0, self.label_offset, ctx.screen_store.getStr(label_handle).*, .{});
            }
        },
        .single_cell => |symbols| {
            _ = ctx.view.writeCell(0, 0, symbols.top_left, .{
                .styling = self.border_style.top_left,
            });

            if (ctx.view.size.x < 2) {
                break :draw_frame;
            } else if (ctx.view.size.x > 2) {
                ctx.view.fill(0, 1, 1, ctx.view.size.x - 2, symbols.top, .{
                    .styling = self.border_style.top,
                });

                if (self.label.maybeValid()) |label_handle| {
                    _ = try ctx.view.write(0, 1 + self.label_offset, ctx.screen_store.getStr(label_handle).*, .{
                        .max_width = ctx.view.size.x -| 2 -| self.label_offset,
                    });
                }

                ctx.view.fill(ctx.view.size.y -| 1, 1, 1, ctx.view.size.x - 2, symbols.bottom, .{
                    .styling = self.border_style.bottom,
                });
            }

            _ = ctx.view.writeCell(0, ctx.view.size.x -| 1, symbols.top_right, .{
                .styling = self.border_style.top_right,
            });

            _ = ctx.view.writeCell(ctx.view.size.y -| 1, 0, symbols.bottom_left, .{
                .styling = self.border_style.bottom_left,
            });

            if (ctx.view.size.y > 2) {
                ctx.view.fill(1, 0, ctx.view.size.y - 2, 1, symbols.left, .{
                    .styling = self.border_style.left,
                });

                ctx.view.fill(1, ctx.view.size.x -| 1, ctx.view.size.y - 2, 1, symbols.right, .{
                    .styling = self.border_style.right,
                });
            }

            _ = ctx.view.writeCell(ctx.view.size.y -| 1, ctx.view.size.x -| 1, symbols.bottom_right, .{
                .styling = self.border_style.bottom_right,
            });
        },
    }

    const padding = switch (self.padding) {
        .none => ScreenVec.zero,
        .all => |v| ScreenVec{ .x = v * 2, .y = v * 2 },
        .sides => |sides| ScreenVec{ .x = sides.left + sides.right, .y = sides.top + sides.bottom },
    };

    var border = switch (self.border) {
        .none => ScreenVec.zero,
        .single_cell => ScreenVec{ .x = 2, .y = 2 },
    };
    if (self.label.maybeValid()) |_| {
        border = border.max(ScreenVec{ .x = 0, .y = 1 });
    }

    const self_element = ctx.tree.get(self_ctx.handle);
    const child_handle = self_element.first_child.maybeValid() orelse {
        return;
    };

    const child_layout_data = ctx.tree.getLayoutData(child_handle);
    const child_view = ctx.view.view(.{
        .pos = child_layout_data.pos,
        .size = child_layout_data.size.min(ctx.view.size.sub(padding).sub(border)),
    });

    const child_rel_pos: ?ScreenVec = blk: {
        const rel_pos = ctx.mouse_rel_pos orelse break :blk null;
        var pos = rel_pos.sub(child_layout_data.pos);

        const child_end = child_layout_data.pos.add(child_layout_data.size);
        if (rel_pos.x >= child_end.x) {
            pos.x = child_layout_data.size.x -| 1;
        }
        if (rel_pos.y >= child_end.y) {
            pos.y = child_layout_data.size.y -| 1;
        }

        break :blk pos;
    };

    const child_ctx = ctx.child(child_view, child_rel_pos);
    const child = ctx.tree.get(child_handle);
    try child.interface.draw(&child_ctx);
}

fn onEvent(self_ctx: Element.SelfContext, ctx: *const Element.OnEventContext) Element.OnEventError!void {
    const child_handle = ctx.tree.get(self_ctx.handle).first_child;
    if (child_handle.isInvalid()) {
        return;
    }
    const child_layout_data = ctx.tree.getLayoutData(child_handle);

    const child_rel_pos: ?ScreenVec = blk: {
        const rel_pos = ctx.mouse_rel_pos orelse break :blk null;
        var pos = rel_pos.sub(child_layout_data.pos);

        const child_end = child_layout_data.pos.add(child_layout_data.size);
        if (rel_pos.x >= child_end.x) {
            pos.x = child_layout_data.size.x -| 1;
        }
        if (rel_pos.y >= child_end.y) {
            pos.y = child_layout_data.size.y -| 1;
        }

        break :blk pos;
    };

    const child_ctx = ctx.child(child_rel_pos);
    const child = ctx.tree.get(child_handle);
    try child.interface.onEvent(&child_ctx);
}

pub const Padding = union(enum) {
    none,
    all: u16,
    sides: Sides,

    pub const Sides = struct {
        top: u16 = 0,
        bottom: u16 = 0,
        left: u16 = 0,
        right: u16 = 0,
    };
};

pub const Border = union(enum) {
    none,
    /// guarantees that all symbols are one cell wide
    single_cell: Symbols,
    // custom: Symbols,

    pub const Symbols = struct {
        top: Cell.Content,
        bottom: Cell.Content,
        left: Cell.Content,
        right: Cell.Content,

        top_left: Cell.Content,
        top_right: Cell.Content,
        bottom_left: Cell.Content,
        bottom_right: Cell.Content,
    };

    pub const line = Border{ .single_cell = Symbols{
        .top = .from(BoxDrawing.LightHorizontal),
        .bottom = .from(BoxDrawing.LightHorizontal),
        .left = .from(BoxDrawing.LightVertical),
        .right = .from(BoxDrawing.LightVertical),

        .top_left = .from(BoxDrawing.LightDownAndRight),
        .top_right = .from(BoxDrawing.LightDownAndLeft),
        .bottom_left = .from(BoxDrawing.LightUpAndRight),
        .bottom_right = .from(BoxDrawing.LightUpAndLeft),
    } };

    pub const heavy_line = Border{ .single_cell = Symbols{
        .top = .from(BoxDrawing.HeavyHorizontal),
        .bottom = .from(BoxDrawing.HeavyHorizontal),
        .left = .from(BoxDrawing.HeavyVertical),
        .right = .from(BoxDrawing.HeavyVertical),

        .top_left = .from(BoxDrawing.HeavyDownAndRight),
        .top_right = .from(BoxDrawing.HeavyDownAndLeft),
        .bottom_left = .from(BoxDrawing.HeavyUpAndRight),
        .bottom_right = .from(BoxDrawing.HeavyUpAndLeft),
    } };

    pub const rounded = Border{ .single_cell = Symbols{
        .top = .from(BoxDrawing.LightHorizontal),
        .bottom = .from(BoxDrawing.LightHorizontal),
        .left = .from(BoxDrawing.LightVertical),
        .right = .from(BoxDrawing.LightVertical),

        .top_left = .from(BoxDrawing.LightArcDownAndRight),
        .top_right = .from(BoxDrawing.LightArcDownAndLeft),
        .bottom_left = .from(BoxDrawing.LightArcUpAndRight),
        .bottom_right = .from(BoxDrawing.LightArcUpAndLeft),
    } };

    pub const double = Border{ .single_cell = Symbols{
        .top = .from(BoxDrawing.DoubleHorizontal),
        .bottom = .from(BoxDrawing.DoubleHorizontal),
        .left = .from(BoxDrawing.DoubleVertical),
        .right = .from(BoxDrawing.DoubleVertical),

        .top_left = .from(BoxDrawing.DoubleDownAndRight),
        .top_right = .from(BoxDrawing.DoubleDownAndLeft),
        .bottom_left = .from(BoxDrawing.DoubleUpAndRight),
        .bottom_right = .from(BoxDrawing.DoubleUpAndLeft),
    } };
};

pub const BorderStyle = struct {
    top: ScreenStore.StylingHandle = .invalid,
    bottom: ScreenStore.StylingHandle = .invalid,
    left: ScreenStore.StylingHandle = .invalid,
    right: ScreenStore.StylingHandle = .invalid,

    top_left: ScreenStore.StylingHandle = .invalid,
    top_right: ScreenStore.StylingHandle = .invalid,
    bottom_left: ScreenStore.StylingHandle = .invalid,
    bottom_right: ScreenStore.StylingHandle = .invalid,
};
