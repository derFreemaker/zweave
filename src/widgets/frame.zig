const std = @import("std");

const ScreenVec = @import("../common/screen_vec.zig");
const Cell = @import("../screen/cell.zig");
const ScreenStore = @import("../screen/screen_store.zig");
const Element = @import("../tree/element.zig");

const BoxDrawing = @import("../symbols/box_drawing.zig");

const Frame = @This();

padding: Padding = .none,
border: Border = .none,
border_style: BorderStyle = .{},

label_offset: u16 = 0,
label: ScreenStore.StrHandle = .invalid,

pub fn element(self: *Frame) Element.Interface {
    return Element.Interface{ .ptr = self, .vtable = &Element.Interface.VTable{
        .getDebugStr = getDebugStr,

        .computeLayout = computeLayout,
        .draw = draw,
    } };
}

fn getDebugStr(self_ctx: Element.SelfContext, ctx: *const Element.GetDebugStrContext) Element.GetDebugStrError![]const u8 {
    _ = self_ctx;
    _ = ctx;

    return "<Frame>";
}

fn computeLayout(self_ctx: Element.SelfContext, ctx: *const Element.ComputeLayoutContext) Element.ComputeLayoutError!ScreenVec {
    const self = self_ctx.get(Frame);

    var border = switch (self.border) {
        .none => ScreenVec.zero,
        .single_cell => ScreenVec{ .x = 2, .y = 2 },
    };
    if (self.label.maybeValid()) |_| {
        border = border.max(ScreenVec{ .x = 0, .y = 1 });
    }

    const self_element = ctx.tree.getMut(self_ctx.handle);
    const child_handle = self_element.first_child.maybeValid() orelse {
        if (self.label.maybeValid()) |label_handle| {
            border = ScreenVec{
                .x = @intCast(border.x + self.label_offset + ctx.strWidth(ctx.screen_store.getStr(label_handle))),
                .y = @max(border.y, 1),
            };
        }
        return border;
    };

    const padding = switch (self.padding) {
        .none => ScreenVec.zero,
        .all => |v| ScreenVec{ .x = v * 2, .y = v * 2 },
        .sides => |sides| ScreenVec{ .x = sides.left + sides.right, .y = sides.top + sides.bottom },
    };

    const child = ctx.tree.getMut(child_handle);

    const child_available = ctx.available.sub(padding).sub(border);
    const child_ctx = ctx.child(child_available);
    const child_size = (try child.interface.computeLayout(&child_ctx)).min(child_available);

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

    const child_data = ctx.tree.getLayoutDataMut(child_handle);
    child_data.pos = padding_top_left.add(border_top_left);
    child_data.size = child_size;

    var requested_size = child_size.add(padding).add(border);
    if (self.label.maybeValid()) |label_handle| {
        const width_border: u16 = switch (self.border) {
            .none => 0,
            .single_cell => 2,
        };

        const width_label = ctx.strWidth(ctx.screen_store.getStr(label_handle));

        requested_size = requested_size.max(ScreenVec{ .x = @intCast(self.label_offset + width_label + width_border), .y = 1 });
    }

    return requested_size;
}

fn draw(self_ctx: Element.SelfContext, ctx: *const Element.DrawContext) Element.DrawError!void {
    const self = self_ctx.get(Frame);

    draw_frame: switch (self.border) {
        .none => {
            if (self.label.maybeValid()) |label_handle| {
                _ = try ctx.view.write(0, self.label_offset, ctx.screen_store.getStr(label_handle), .{});
            }
        },
        .single_cell => |symbols| {
            _ = ctx.view.writeCell(null, 0, 0, symbols.top_left, .{
                .style = self.border_style.top_left,
            });

            if (ctx.view.size.x < 2) {
                break :draw_frame;
            } else if (ctx.view.size.x > 2) {
                ctx.view.fill(null, 0, 1, 1, ctx.view.size.x - 2, symbols.top, .{
                    .style = self.border_style.top,
                });

                if (self.label.maybeValid()) |label_handle| {
                    _ = try ctx.view.write(0, 1 + self.label_offset, ctx.screen_store.getStr(label_handle), .{
                        .max_width = ctx.view.size.x -| 2 -| self.label_offset,
                    });
                }

                ctx.view.fill(null, ctx.view.size.y -| 1, 1, 1, ctx.view.size.x - 2, symbols.bottom, .{
                    .style = self.border_style.bottom,
                });
            }

            _ = ctx.view.writeCell(null, 0, ctx.view.size.x -| 1, symbols.top_right, .{
                .style = self.border_style.top_right,
            });

            _ = ctx.view.writeCell(null, ctx.view.size.y -| 1, 0, symbols.bottom_left, .{
                .style = self.border_style.bottom_left,
            });

            if (ctx.view.size.y > 2) {
                ctx.view.fill(null, 1, 0, ctx.view.size.y - 2, 1, symbols.left, .{
                    .style = self.border_style.left,
                });

                ctx.view.fill(null, 1, ctx.view.size.x -| 1, ctx.view.size.y - 2, 1, symbols.right, .{
                    .style = self.border_style.right,
                });
            }

            _ = ctx.view.writeCell(null, ctx.view.size.y -| 1, ctx.view.size.x -| 1, symbols.bottom_right, .{
                .style = self.border_style.bottom_right,
            });
        },
    }

    const self_element = ctx.tree.get(self_ctx.handle);
    const child_handle = self_element.first_child.maybeValid() orelse {
        return;
    };

    const child_layout_data = ctx.tree.getLayoutData(child_handle);
    const child_view = ctx.view.viewVec(.{
        .pos = child_layout_data.pos,
        .size = child_layout_data.size,
    });

    const child_ctx = ctx.child(child_view);
    const child = ctx.tree.get(child_handle);
    try child.interface.draw(&child_ctx);
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
    top: ScreenStore.StyleHandle = .invalid,
    bottom: ScreenStore.StyleHandle = .invalid,
    left: ScreenStore.StyleHandle = .invalid,
    right: ScreenStore.StyleHandle = .invalid,

    top_left: ScreenStore.StyleHandle = .invalid,
    top_right: ScreenStore.StyleHandle = .invalid,
    bottom_left: ScreenStore.StyleHandle = .invalid,
    bottom_right: ScreenStore.StyleHandle = .invalid,
};
