const std = @import("std");

const tracy = @import("tracy");
const zttio = @import("zttio");

const UnderlyingScreen = @import("../screen/screen.zig");
const ScreenStore = @import("../screen/screen_store.zig");
const ScreenVec = @import("../screen/screen_vec.zig");
const Styling = @import("../screen/styling.zig").Styling;
const ScreenView = @import("../screen/view.zig");
const Element = @import("../tree/element.zig");
const Unicode = @import("../unicode.zig");

const Screen = @This();

view: ScreenView,

pub fn init(allocator: std.mem.Allocator, opts: ScreenOptions) std.mem.Allocator.Error!Screen {
    const screen = try allocator.create(UnderlyingScreen);
    errdefer allocator.destroy(screen);

    screen.* = try UnderlyingScreen.init(
        allocator,
        opts.store,
        opts.size,
        opts.width_method,
    );
    errdefer screen.deinit();

    return Screen{
        .view = screen.view(.{}),
    };
}

pub fn deinit(self: *Screen, allocator: std.mem.Allocator) void {
    self.view.screen.deinit();
    allocator.destroy(self.view.screen);
}

pub fn element(self: *Screen) Element.Interface {
    return Element.Interface{ .ptr = self, .vtable = &Element.Interface.VTable{
        .getDebugStr = getDebugStr,

        .computeLayout = computeLayout,
        .draw = draw,
    } };
}

fn getDebugStr(self_ctx: Element.SelfContext, ctx: *const Element.GetDebugStrContext) Element.GetDebugStrError![]const u8 {
    const self = self_ctx.get(Screen);

    const screen_size = self.view.screen.size;
    return std.fmt.allocPrint(ctx.allocator, "<Screen w:{d} h:{d}>", .{ screen_size.x, screen_size.y });
}

fn computeLayout(self_ctx: Element.SelfContext, ctx: *const Element.ComputeLayoutContext) Element.ComputeLayoutError!ScreenVec {
    const self = self_ctx.get(Screen);
    _ = ctx;

    return ScreenVec{
        .x = self.view.size.x,
        .y = self.view.size.y,
    };
}

fn draw(self_ctx: Element.SelfContext, ctx: *const Element.DrawContext) Element.DrawError!void {
    const self = self_ctx.get(Screen);

    try ctx.view.projectView(&self.view, 0, 0);
}

pub const ScreenOptions = struct {
    store: *ScreenStore,
    size: ScreenVec,
    width_method: Unicode.WidthMethod,
};
