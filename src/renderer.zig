const std = @import("std");
const zttio = @import("zttio");

const Screen = @import("screen/screen.zig");
const ScreenStore = @import("screen/screen_store.zig");
const Tree = @import("tree/tree.zig");

const Renderer = @This();

prev: *Screen,
next: *Screen,

pub fn init(allocator: std.mem.Allocator, winsize: zttio.Winsize, unicode_width_method: zttio.gwidth.Method) std.mem.Allocator.Error!Renderer {
    var first_screen = try allocator.create(Screen);
    first_screen.* = try Screen.init(allocator, winsize, unicode_width_method);
    errdefer first_screen.deinit();

    var second_screen = try allocator.create(Screen);
    second_screen.* = try Screen.init(allocator, winsize, unicode_width_method);
    errdefer second_screen.deinit(allocator);

    return Renderer{
        .prev = first_screen,
        .next = second_screen,
    };
}

pub fn deinit(self: *Renderer, allocator: std.mem.Allocator) void {
    self.prev.deinit();
    allocator.destroy(self.prev);

    self.next.deinit();
    allocator.destroy(self.next);
}

pub inline fn getScreen(self: *const Renderer) *Screen {
    return self.next;
}

pub fn resize(self: *Renderer, new_winsize: zttio.Winsize) std.mem.Allocator.Error!void {
    try self.next.resize(new_winsize);
    try self.prev.resize(new_winsize);
}

pub fn render(self: *Renderer, screen_store: *const ScreenStore, tty: *zttio.Tty) error{UnableToRender}!void {
    tty.startSync() catch {};

    const next = self.next;
    next.renderDirect(screen_store, tty) catch return error.UnableToRender;

    tty.endSync() catch {};

    self.next = self.prev;
    self.prev = next;
}
