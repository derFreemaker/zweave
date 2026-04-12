const std = @import("std");

const ScreenVec = @import("../common/screen_vec.zig");
const Cell = @import("../screen/cell.zig");
const ScreenStore = @import("../screen/screen_store.zig");
const Element = @import("../tree/element.zig");

const BoxDrawing = @import("../symbols/box_drawing.zig");

const Frame = @This();

padding: Padding = .{ .sides = .{
    .left = 1,
    .right = 1,
} },
border: Border = .none,
boder_style: BorderStyle = .{},

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
    const self_element = ctx.tree.getMut(self_ctx.handle);
    // if (!self_element.isDirty and !self_element.childIsDirty) {
    //     return ctx.tree.getLayoutData(self_ctx.handle).size;
    // }

    const child_handle = self_element.first_child.notInvalid() orelse {
        return .zero;
    };

    const self = self_ctx.get(Frame);

    const padding = switch (self.padding) {
        .all => |v| ScreenVec{ .x = v * 2, .y = v * 2 },
        .sides => |sides| ScreenVec{ .x = sides.left + sides.right, .y = sides.top + sides.bottom },
    };

    const border = switch (self.border) {
        .none => ScreenVec.zero,
        .single_cell => ScreenVec{ .x = 2, .y = 2 },
    };

    const child = ctx.tree.getMut(child_handle);

    const child_available = ctx.available.sub(padding).sub(border);
    const child_ctx = ctx.child(child_available);
    const child_size = try child.interface.computeLayout(&child_ctx);

    const padding_top_left = switch (self.padding) {
        .all => |v| ScreenVec{ .x = v, .y = v },
        .sides => |sides| ScreenVec{
            .x = sides.left,
            .y = sides.top,
        },
    };

    const border_top_left = switch (self.border) {
        .none => ScreenVec.zero,
        .single_cell => ScreenVec{ .x = 1, .y = 1 },
    };

    const child_data = ctx.tree.getLayoutDataMut(child_handle);
    child_data.pos = padding_top_left.add(border_top_left);
    child_data.size = child_size.min(child_available);

    // child.isDirty = false;
    // self_element.childIsDirty = false;

    return child_size.add(padding).add(border);
}

fn draw(self_ctx: Element.SelfContext, ctx: *const Element.DrawContext) Element.DrawError!void {
    const self = self_ctx.get(Frame);

    switch (self.border) {
        .none => {},
        .single_cell => |symbols| {
            _ = ctx.view.writeCell(null, 0, 0, symbols.top_left, .{
                .style = self.boder_style.top_left,
            });

            _ = ctx.view.writeCell(null, 0, ctx.view.size.x -| 1, symbols.top_right, .{
                .style = self.boder_style.top_right,
            });

            _ = ctx.view.writeCell(null, ctx.view.size.y -| 1, 0, symbols.bottom_left, .{
                .style = self.boder_style.bottom_left,
            });

            _ = ctx.view.writeCell(null, ctx.view.size.y -| 1, ctx.view.size.x -| 1, symbols.bottom_right, .{
                .style = self.boder_style.bottom_right,
            });

            if (ctx.view.size.x > 2) {
                ctx.view.fill(null, 0, 1, 1, ctx.view.size.x - 2, symbols.top, .{
                    .style = self.boder_style.top,
                });

                ctx.view.fill(null, ctx.view.size.y -| 1, 1, 1, ctx.view.size.x - 2, symbols.bottom, .{
                    .style = self.boder_style.bottom,
                });
            }

            if (ctx.view.size.y > 2) {
                ctx.view.fill(null, 1, 0, ctx.view.size.y - 2, 1, symbols.left, .{
                    .style = self.boder_style.left,
                });

                ctx.view.fill(null, 1, ctx.view.size.x -| 1, ctx.view.size.y - 2, 1, symbols.right, .{
                    .style = self.boder_style.right,
                });
            }
        },
    }

    const self_element = ctx.tree.get(self_ctx.handle);
    const child_handle = self_element.first_child.notInvalid() orelse {
        return;
    };

    const child_layout_data = ctx.tree.getLayoutData(child_handle);
    const child_view = ctx.view.view(.{
        .col = child_layout_data.pos.x,
        .row = child_layout_data.pos.y,

        .width = child_layout_data.size.x,
        .height = child_layout_data.size.y,
    });

    const child_ctx = ctx.child(child_view);
    const child = ctx.tree.get(child_handle);
    try child.interface.draw(&child_ctx);
}

pub const Padding = union(enum) {
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
