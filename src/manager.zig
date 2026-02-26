const std = @import("std");

const zttio = @import("zttio");

const Tree = @import("tree.zig");
const Element = @import("element.zig");
const Renderer = @import("renderer.zig");

const Container = @import("components/container.zig");

const Manager = @This();

allocator: std.mem.Allocator,
arena: std.heap.ArenaAllocator,

tty: *zttio.Tty,
tree: Tree,
renderer: Renderer,

root: Element.Handle,

pub const InitError = error{UnableToInitTty} || std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator) InitError!Manager {
    const arena = std.heap.ArenaAllocator.init(allocator);

    var tty = zttio.Tty.init(
        allocator,
        allocator,
        .stdin(),
        .stdout(),
        .{},
    ) catch return error.UnableToInitTty;
    errdefer tty.deinit();

    var tree = try Tree.init(allocator);
    errdefer tree.deinit();

    var renderer = try Renderer.init(allocator, tty.getWinsize(), tty.caps.unicode_width_method);
    errdefer renderer.deinit(allocator);

    const root = try allocator.create(Container);
    errdefer allocator.destroy(root);
    root.* = Container.init();

    const root_handle = try tree.create(root.element());

    return Manager{
        .allocator = allocator,
        .arena = arena,

        .tty = tty,
        .tree = tree,
        .renderer = renderer,

        .root = root_handle,
    };
}

pub fn deinit(self: *Manager) void {
    self.tree.deinit();
    self.renderer.deinit(self.allocator);
    self.tty.deinit();
}

pub const RenderError = error{
    UnableToRender,
} || std.mem.Allocator.Error;

pub fn renderNextFrame(self: *Manager) RenderError!void {
    const arena_allocator = self.arena.allocator();

    var screen = self.renderer.getScreen();

    const root = self.tree.get(self.root);
    const needed_space = try root.interface.vtable.computeLayout.?(&Element.CalcLayoutContext{
        .allocator = arena_allocator,
        .tree = &self.tree,

        .self = root,
        .self_handle = self.root,

        .available = .{
            .x = screen.winsize.cols,
            .y = screen.winsize.rows,
        },
    });

    const root_view = screen.view(0, 0, needed_space.x, needed_space.y, .no_overflow);
    try root.interface.vtable.draw(&Element.DrawContext{
        .self = root,
        .self_handle = self.root,

        .view = root_view,
    });

    try self.renderer.render(self.tty);

    self.tty.flush() catch return error.UnableToRender;
}
