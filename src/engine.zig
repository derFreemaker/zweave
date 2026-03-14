const std = @import("std");
const tracy = @import("tracy");
const zttio = @import("zttio");

const Screen = @import("screen/screen.zig");
const CountingAllocator = @import("counting_allocator.zig");
const Tree = @import("tree/tree.zig");
const ScreenStore = @import("screen/screen_store.zig");
const Element = @import("tree/element.zig");
const Renderer = @import("renderer.zig");
const Container = @import("components/container.zig");
const Style = @import("screen/styling.zig").Style;

const Engine = @This();

allocator: std.mem.Allocator,
tree_allocator: CountingAllocator,
render_allocator: CountingAllocator,
arena: std.heap.ArenaAllocator,

tty: *zttio.Tty,
tree: Tree,
screen_store: ScreenStore,
renderer: Renderer,

root_container: Container,
root: Element.Handle,

show_stats: bool,
stats_style: ScreenStore.StyleHandle,

pub const InitError = error{UnableToInitTty} || std.mem.Allocator.Error;

pub fn init_(self: *Engine, allocator: std.mem.Allocator, event_allocator: std.mem.Allocator) InitError!void {
    self.tree_allocator = CountingAllocator.init(allocator);
    self.render_allocator = CountingAllocator.init(allocator);
    self.arena = std.heap.ArenaAllocator.init(allocator);

    self.tty = zttio.Tty.init(
        allocator,
        event_allocator,
        .stdin(),
        .stdout(),
        .{},
    ) catch return error.UnableToInitTty;
    errdefer self.tty.deinit();

    self.tree = try Tree.init(self.tree_allocator.allocator());
    errdefer self.tree.deinit();

    self.screen_store = try ScreenStore.init(self.render_allocator.allocator());
    errdefer self.screen_store.deinit();

    self.renderer = try Renderer.init(self.render_allocator.allocator(), self.tty.getWinsize(), self.tty.caps.unicode_width_method);
    errdefer self.renderer.deinit(allocator);

    self.root_container = Container.init();
    self.root = try self.tree.create(self.root_container.element());
    errdefer self.tree.destroy(self.root);

    self.show_stats = false;
    self.stats_style = try self.screen_store.addStyle(Style{
        .background = .{ .c8 = .black },
        .foreground = .{ .c8 = .green },
    });
    errdefer self.screen_store.removeStyle(self.stats_style);
}

pub fn deinit(self: *Engine) void {
    self.arena.deinit();

    self.renderer.deinit(self.render_allocator.allocator());
    self.screen_store.deinit();
    self.tree.deinit();
    self.tty.deinit();
}

pub inline fn resize(self: *Engine, new_winsize: zttio.Winsize) std.mem.Allocator.Error!void {
    return self.renderer.resize(new_winsize);
}

pub const LayoutError = std.mem.Allocator.Error;

fn computeLayout(self: *Engine, allocator: std.mem.Allocator, screen: *Screen, root: *const Element) LayoutError!Element.SmallVec2 {
    const layout_trace_zone = tracy.Zone.begin(.{
        .name = "[Engine]: layout",
        .src = @src(),
    });
    defer layout_trace_zone.end();

    const needed_space = try root.interface.vtable.computeLayout.?(&Element.CalcLayoutContext{
        .allocator = allocator,
        .tree = &self.tree,
        .width_method = screen.width_method,

        .self = root,
        .self_handle = self.root,

        .available = .{
            .x = screen.winsize.cols,
            .y = screen.winsize.rows,
        },
    });

    return needed_space;
}

pub const RenderError = error{
    UnableToRender,
} || std.mem.Allocator.Error;

pub fn renderNextFrame(self: *Engine) RenderError!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Engine]: renderNextFrame",
        .src = @src(),
    });
    defer trace_zone.end();

    _ = self.arena.reset(.{ .retain_with_limit = 8 * 1024 * 1024 });
    var trace_allocator = tracy.Allocator{
        .pool_name = "[Engine]: FrameArena",
        .parent = self.arena.allocator(),
    };
    const allocator = trace_allocator.allocator();

    var screen = self.renderer.getScreen();
    screen.clear();

    const root = self.tree.get(self.root);
    const needed_space = try self.computeLayout(allocator, screen, root);

    {
        const draw_trace_zone = tracy.Zone.begin(.{
            .name = "[Engine]: draw",
            .src = @src(),
        });
        defer draw_trace_zone.end();

        const root_view = screen.view(.{
            .col = 0,
            .row = 0,
            .width = needed_space.x,
            .height = needed_space.y,
        });

        try root.interface.vtable.draw(&Element.DrawContext{
            .tree = &self.tree,

            .self = root,
            .self_handle = self.root,

            .view = root_view,
            .screen_store = &self.screen_store,
        });
    }

    const stats_view = screen.view(.{
        .col = 0,
        .row = 0,

        .default_style = self.stats_style,
    });

    if (self.show_stats) {
        var alloc_writer = std.Io.Writer.Allocating.init(allocator);
        defer alloc_writer.deinit();
        const writer = &alloc_writer.writer;

        writer.print("Winsize: c-{d}x{d}-{d} p-{d}x{d} \n", .{
            screen.winsize.cols,
            screen.winsize.rows,
            screen.buf.len,
            screen.winsize.x_pixel,
            screen.winsize.y_pixel,
        }) catch return error.UnableToRender;

        {
            _ = writer.write("Memory Usage: ") catch return error.UnableToRender;

            _ = writer.write("Tree-") catch return error.UnableToRender;
            self.tree_allocator.prettyPrintBytesUsed(writer) catch return error.UnableToRender;
            writer.writeByte(' ') catch return error.UnableToRender;

            _ = writer.write("Render-") catch return error.UnableToRender;
            self.render_allocator.prettyPrintBytesUsed(writer) catch return error.UnableToRender;
            writer.writeByte(' ') catch return error.UnableToRender;

            writer.writeByte('\n') catch return error.UnableToRender;
        }

        {
            _ = writer.write("Memory Capacity: ") catch return error.UnableToRender;

            writer.print("DrawLoop-{d:.1}kB", .{
                @as(f64, @floatFromInt(self.arena.queryCapacity())) / 1024,
            }) catch return error.UnableToRender;
            writer.writeByte(' ') catch return error.UnableToRender;

            writer.writeByte('\n') catch return error.UnableToRender;
        }

        writer.flush() catch return error.UnableToRender;

        _ = try stats_view.write(0, 0, alloc_writer.written(), .{});
    }

    try self.renderer.render(&self.screen_store, self.tty);

    self.tty.flush() catch return error.UnableToRender;
}
