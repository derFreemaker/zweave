const std = @import("std");

const Event = @import("../event.zig").Event;
const ScreenStore = @import("../screen/screen_store.zig");
const ScreenVec = @import("../screen/screen_vec.zig");
const Styling = @import("../screen/styling.zig").Styling;
const ScreenView = @import("../screen/view.zig");
const BlockElements = @import("../symbols/block_elements.zig");

const ScrollView = @This();

pos: ScreenVec = ScreenVec.zero,
auto_hide_vertical_scrollbar: bool = true,
auto_hide_horizontal_scrollbar: bool = true,

styling_vertical_scrollbar: Styling = .{},
styling_horizontal_scrollbar: Styling = .{},

// @TODO: make scrollbar more customizable

pub fn scrollTo(self: *ScrollView, pos: ScreenVec) void {
    self.pos = pos;
}

pub fn scrollUp(self: *ScrollView, n: u16) void {
    self.pos.y -|= n;
}

pub fn scrollDown(self: *ScrollView, n: u16) void {
    self.pos.y +|= n;
}

pub fn scrollLeft(self: *ScrollView, n: u16) void {
    self.pos.x -|= n;
}

pub fn scrollRight(self: *ScrollView, n: u16) void {
    self.pos.x +|= n;
}

pub fn clampTo(self: *ScrollView, pos: ScreenVec) void {
    self.pos = self.pos.min(pos);
}

pub fn handleInput(self: *ScrollView, event: *const Event) bool {
    const Mouse = @import("../event.zig").Mouse;
    return switch (event.*) {
        .mouse => |mouse| {
            switch (mouse.switchable()) {
                Mouse.matches(.wheel_up, .press, .{}) => {
                    self.scrollUp(1);
                },
                Mouse.matches(.wheel_down, .press, .{}) => {
                    self.scrollDown(1);
                },
                Mouse.matches(.wheel_left, .press, .{}) => {
                    self.scrollLeft(1);
                },
                Mouse.matches(.wheel_right, .press, .{}) => {
                    self.scrollRight(1);
                },
                else => return false,
            }

            return true;
        },
        else => return false,
    };
}

pub fn adjustAndDraw(self: *const ScrollView, view: ScreenView, total_size: ScreenVec) std.mem.Allocator.Error!ScreenView {
    var adjusted_view = view;
    adjusted_view.mask_offset = self.pos;

    const inverted = self.styling_scrollbar;
    inverted.attrs.reverse = .set;

    const draw_vertical_scrollbar = !self.auto_hide_vertical_scrollbar or total_size.y > adjusted_view.size.y;
    if (draw_vertical_scrollbar) {
        adjusted_view.size.x -|= 1;

        const styling_vertical = try view.screen.addFrameStyling(self.styling_vertical_scrollbar);
        const styling_vertical_inverted = try view.screen.addFrameStyling(blk: {
            var styling_inverted = self.styling_vertical_scrollbar;
            styling_inverted.attrs.reverse = .set;
            break :blk styling_inverted;
        });

        const scrollbar_position: f32 = @as(f32, @floatFromInt(self.pos.y)) / @as(f32, @floatFromInt(total_size.y)) * @as(f32, @floatFromInt(view.size.y));
        const scrollbar_cell_position: u16 = @trunc(scrollbar_position);

        view.fill(0, view.size.x - 1, scrollbar_cell_position, 1, .empty, .{
            .styling = styling_vertical,
        });

        const size_of_first_part = 1 - (scrollbar_position - @as(f32, @floatFromInt(scrollbar_cell_position)));
        const first_part = getVerticalScrollbarPart(size_of_first_part);
        _ = view.writeCell(scrollbar_cell_position, view.size.x - 1, .from(first_part), .{
            .styling = styling_vertical,
        });

        const scrollbar_height_rel: f32 = @as(f32, @floatFromInt(view.size.y)) / @as(f32, @floatFromInt(total_size.y));
        const scrollbar_height: f32 = @max(view.size.y * scrollbar_height_rel - size_of_first_part, 0);
        const scrollbar_cell_height: u16 = @trunc(scrollbar_height);

        view.fill(scrollbar_cell_position + 1, view.size.x - 1, scrollbar_cell_height, 1, .from(BlockElements.FullBlock), .{
            .styling = styling_vertical,
        });

        const size_of_last_part = scrollbar_height - @as(f32, @floatFromInt(scrollbar_cell_height));
        if (size_of_last_part > 0) {
            const last_part = getVerticalScrollbarPart(size_of_last_part);
            _ = view.writeCell(scrollbar_cell_position + scrollbar_cell_height + 1, view.size.x - 1, .from(last_part), .{
                .styling = styling_vertical_inverted,
            });
        }

        const cell_position_after_scrollbar = scrollbar_cell_position + scrollbar_cell_height + 1 + if (size_of_last_part == 0) @as(u16, 0) else @as(u16, 1);
        view.fill(cell_position_after_scrollbar, view.size.x - 1, view.size.y -| scrollbar_cell_position -| scrollbar_cell_height, 1, .empty, .{
            .styling = styling_vertical,
        });
    }

    const draw_horizontal_scrollbar = !self.auto_hide_horizontal_scrollbar or total_size.x > adjusted_view.size.x;
    _ = draw_horizontal_scrollbar; // autofix
    // if (draw_horizontal_scrollbar) {
    //     adjusted_view.size.y -|= 1;

    //     const scrollbar_position: f32 = @as(f32, self.pos.x) / @as(f32, total_size.x);
    //     _ = scrollbar_position; // autofix

    //     const scrollbar_height_rel: f32 = @as(f32, adjusted_view.size.x) / @as(f32, total_size.x);
    //     const scrollbar_height: f32 = @max(adjusted_view.size.x * scrollbar_height_rel, 0.125);
    //     _ = scrollbar_height; // autofix

    //     //@TODO: draw scrollbar
    // }

    return adjusted_view;
}

fn getVerticalScrollbarPart(n: f32) []const u8 {
    std.debug.assert(0 <= n and n <= 1);

    if (n > 0.875) {
        return BlockElements.FullBlock;
    } else if (n > 0.750) {
        return BlockElements.Lower_7_8_Block;
    } else if (n > 0.625) {
        return BlockElements.Lower_6_8_Block;
    } else if (n > 0.500) {
        return BlockElements.Lower_5_8_Block;
    } else if (n > 0.375) {
        return BlockElements.Lower_4_8_Block;
    } else if (n > 0.250) {
        return BlockElements.Lower_3_8_Block;
    } else if (n > 0.125) {
        return BlockElements.Lower_2_8_Block;
    } else if (n > 0) {
        return BlockElements.Lower_1_8_Block;
    }

    unreachable;
}
