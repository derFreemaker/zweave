const std = @import("std");
const zttio = @import("zttio");

const Screen = @import("screen.zig");
const Tree = @import("tree.zig");

const Renderer = @This();

prev: *Screen,
next: *Screen,

pub fn init(allocator: std.mem.Allocator, winsize: zttio.Winsize, unicode_width_method: zttio.gwidth.Method) std.mem.Allocator.Error!Renderer {
    var first_screen = try allocator.create(Screen);
    first_screen.* = try Screen.init(allocator, winsize, unicode_width_method);
    errdefer first_screen.deinit();

    var second_screen = try allocator.create(Screen);
    second_screen.* = try Screen.init(allocator, winsize, unicode_width_method);
    errdefer second_screen.deinit();

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

pub fn render(self: *Renderer, tty: *zttio.Tty) error{UnableToRender}!void {
    const next = self.next;
    next.renderDirect(tty) catch return error.UnableToRender;

    self.next = self.prev;
    self.prev = next;
}
