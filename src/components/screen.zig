const std = @import("std");
const tracy = @import("tracy");
const zttio = @import("zttio");

const Unicode = @import("../common/unicode.zig");
const ScreenVec = @import("../common/screen_vec.zig");
const UnderlyingScreen = @import("../screen/screen.zig");
const ScreenView = @import("../screen/view.zig");
const ScreenStore = @import("../screen/screen_store.zig");
const Element = @import("../tree/element.zig");
const LayoutConstraints = @import("../layout/layout_constraints.zig");

const Screen = @import("screen.zig");

view: ScreenView,

pub fn init(allocator: std.mem.Allocator, opts: ScreenOptions) std.mem.Allocator.Error!Screen {
    const screen = try allocator.create(UnderlyingScreen);
    errdefer allocator.destroy(screen);

    screen.* = try UnderlyingScreen.init(
        allocator,
        opts.size,
        opts.width_method,
    );
    errdefer screen.deinit();

    const view = screen.view(.{
        .row = 0,
        .col = 0,
        .default_style = opts.default_style,
    });

    return Screen{
        .view = view,
    };
}

pub fn deinit(self: *Screen, allocator: std.mem.Allocator) void {
    self.view.screen.deinit();
    allocator.destroy(self.view.screen);
}

pub fn element(self: *Screen) Element.Interface {
    return Element.Interface{ .ptr = self, .vtable = &Element.Interface.VTable{
        .getLayoutConstraints = getLayoutConstraints,
        .draw = draw,
    } };
}

pub fn getLayoutConstraints(self_ptr: *anyopaque, ctx: *const Element.GetLayoutConstraintsContext) Element.GetLayoutConstraintsError!LayoutConstraints {
    const self: *Screen = @ptrCast(@alignCast(self_ptr));
    _ = ctx;

    return LayoutConstraints{
        .height = .{ .fixed = self.view.size.y },
        .width = .{ .fixed = self.view.size.x },
    };
}

pub fn draw(self_ptr: *anyopaque, ctx: *const Element.DrawContext) Element.DrawError!void {
    const self: *Screen = @ptrCast(@alignCast(self_ptr));

    try ctx.view.projectView(&self.view, 0, 0);
}

pub const ScreenOptions = struct {
    size: ScreenVec,
    width_method: Unicode.WidthMethod,

    default_style: ScreenStore.StyleHandle = .invalid,
};
