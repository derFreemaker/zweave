const std = @import("std");
const zttio = @import("zttio");

const CountingAllocator = @import("counting_allocator.zig");
const Tree = @import("tree.zig");
const Element = @import("element.zig");
const Renderer = @import("renderer.zig");
const Container = @import("components/container.zig");

const Manager = @This();

allocator: std.mem.Allocator,
tree_allocator: CountingAllocator,
render_allocator: CountingAllocator,
arena: std.heap.ArenaAllocator,

tty: *zttio.Tty,
tree: Tree,
renderer: Renderer,

root_container: Container,
root: Element.Handle,

showStats: bool = false,

pub const InitError = error{UnableToInitTty} || std.mem.Allocator.Error;

pub fn init_(self: *Manager, allocator: std.mem.Allocator) InitError!void {
    self.tree_allocator = CountingAllocator.init(allocator);
    self.render_allocator = CountingAllocator.init(allocator);
    self.arena = std.heap.ArenaAllocator.init(allocator);

    self.tty = zttio.Tty.init(
        allocator,
        allocator,
        .stdin(),
        .stdout(),
        .{},
    ) catch return error.UnableToInitTty;
    errdefer self.deinit();

    self.tree = try Tree.init(self.tree_allocator.allocator());
    errdefer self.deinit();

    self.renderer = try Renderer.init(self.render_allocator.allocator(), self.tty.getWinsize(), self.tty.caps.unicode_width_method);
    errdefer self.renderer.deinit(allocator);

    self.root_container = Container.init();
    self.root = try self.tree.create(self.root_container.element());
}

pub fn deinit(self: *Manager) void {
    self.arena.deinit();

    self.tree.deinit();
    self.renderer.deinit(self.render_allocator.allocator());
    self.tty.deinit();
}

pub const RenderError = error{
    UnableToRender,
} || std.mem.Allocator.Error;

pub fn renderNextFrame(self: *Manager) RenderError!void {
    _ = self.arena.reset(.{ .retain_with_limit = 8 * 1024 * 1024 });
    const allocator = self.arena.allocator();

    var screen = self.renderer.getScreen();
    screen.clear();

    const root = self.tree.get(self.root);
    const needed_space = try root.interface.vtable.computeLayout.?(&Element.CalcLayoutContext{
        .allocator = allocator,
        .tree = &self.tree,

        .self = root,
        .self_handle = self.root,

        .available = .{
            .x = screen.winsize.cols,
            .y = screen.winsize.rows,
        },
    });
    const root_view = screen.view(0, 0, needed_space.x, needed_space.y, .allow_overflow);
    try root.interface.vtable.draw(&Element.DrawContext{
        .self = root,
        .self_handle = self.root,

        .view = root_view,
    });

    const stats_view = screen.view(0, 0, null, null, .allow_overflow);

    if (self.showStats) {
        const winsize_str = try std.fmt.allocPrint(allocator, "Winsize: c-{d}x{d}-{d} p-{d}x{d} ", .{
            screen.winsize.cols,
            screen.winsize.rows,
            screen.capacity,
            screen.winsize.x_pixel,
            screen.winsize.y_pixel,
        });
        defer allocator.free(winsize_str);
        _ = try stats_view.write(0, 0, winsize_str, .{});

        var mem_pos: u16 = 0;
        mem_pos += try stats_view.write(mem_pos, 1, "Memory Usage: ", .{});

        mem_pos += try stats_view.write(mem_pos, 1, "Tree-", .{});
        const tree_mem_str = try self.tree_allocator.prettyPrintBytesUsed(allocator);
        defer allocator.free(tree_mem_str);
        mem_pos += try stats_view.write(mem_pos, 1, tree_mem_str, .{});
        mem_pos += try stats_view.write(mem_pos, 1, " ", .{});

        mem_pos += try stats_view.write(mem_pos, 1, "Render-", .{});
        const render_mem_str = try self.render_allocator.prettyPrintBytesUsed(allocator);
        defer allocator.free(render_mem_str);
        mem_pos += try stats_view.write(mem_pos, 1, render_mem_str, .{});
        mem_pos += try stats_view.write(mem_pos, 1, " ", .{});

        const mem_str = try std.fmt.allocPrint(allocator, "Memory Capacity: DrawLoop-{d:.1}kB ", .{
            @as(f64, @floatFromInt(self.arena.queryCapacity())) / 1024,
        });
        defer allocator.free(mem_str);

        _ = try stats_view.write(0, 2, mem_str, .{});
    }

    try self.renderer.render(self.tty);

    self.tty.flush() catch return error.UnableToRender;
}
