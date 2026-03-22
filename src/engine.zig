const std = @import("std");
const tracy = @import("tracy");
const zttio = @import("zttio");

const ScreenVec = @import("common/screen_vec.zig");
const CountingAllocator = @import("common/counting_allocator.zig");
const Container = @import("components/container.zig");
const Screen = @import("screen/screen.zig");
const ScreenStore = @import("screen/screen_store.zig");
const Style = @import("screen/styling.zig").Style;
const Tree = @import("tree/tree.zig");
const Element = @import("tree/element.zig");
const Renderer = @import("renderer.zig");
const Event = @import("event.zig").Event;

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

last_frame_time: i64,

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

    const winsize = self.tty.getWinsize();
    const screen_size = ScreenVec{ .x = winsize.cols, .y = winsize.rows };
    self.renderer = try Renderer.init(self.render_allocator.allocator(), screen_size, self.tty.caps.unicode_width_method);
    errdefer self.renderer.deinit(allocator);

    self.root_container = Container.init();
    self.root = try self.tree.create(self.root_container.element());
    errdefer self.tree.destroy(self.root);

    self.show_stats = false;
    self.stats_style = try self.screen_store.addStyle(Style{
        .inherit = true,
        .attrs = .{ .reverse = true },
    });
    errdefer self.screen_store.removeStyle(self.stats_style);

    self.last_frame_time = 0;
}

pub fn deinit(self: *Engine) void {
    self.arena.deinit();

    self.renderer.deinit(self.render_allocator.allocator());
    self.screen_store.deinit();
    self.tree.deinit();
    self.tty.deinit();
}

pub inline fn resize(self: *Engine, new_size: ScreenVec) std.mem.Allocator.Error!void {
    return self.renderer.resize(new_size);
}

pub fn dispatchEventToFocusedElement(self: *Engine, event: Event) std.mem.Allocator.Error!void {
    if (self.tree.isFocused(.invalid)) return;
    const element = self.tree.get(self.tree.focused_element);

    try element.interface.onEvent(&Element.EventContext{
        .tree = &self.tree,

        .handle = self.tree.focused_element,

        .event = &event,
    });
}

pub const LayoutError = std.mem.Allocator.Error;

fn computeLayout(self: *Engine, allocator: std.mem.Allocator, screen: *Screen, root: *const Element) LayoutError!ScreenVec {
    const layout_trace_zone = tracy.Zone.begin(.{
        .name = "[Engine]: layout",
        .src = @src(),
    });
    defer layout_trace_zone.end();

    const needed_space = try root.interface.computeLayout(&Element.CalcLayoutContext{
        .allocator = allocator,
        .tree = &self.tree,
        .width_method = screen.width_method,

        .handle = self.root,

        .available = screen.size,
    });

    return needed_space;
}

pub fn renderNextFrame(self: *Engine) Renderer.RenderError!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Engine]: renderNextFrame",
        .src = @src(),
    });
    defer trace_zone.end();

    const start = std.time.microTimestamp();

    _ = self.arena.reset(.{ .retain_with_limit = 8 * 1024 * 1024 });
    var trace_allocator = tracy.Allocator{
        .pool_name = "[Engine]: FrameArena",
        .parent = self.arena.allocator(),
    };
    const allocator = trace_allocator.allocator();

    var screen = self.renderer.prepareNextFrameScreen();

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

        try root.interface.draw(&Element.DrawContext{
            .tree = &self.tree,

            .handle = self.root,

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
        const stats_trace_zone = tracy.Zone.begin(.{
            .name = "[Engine]: stats write",
            .src = @src(),
        });
        defer stats_trace_zone.end();

        var stats_buf: [128]u8 = undefined;
        var stats_writer = stats_view.writer(&stats_buf);
        const writer = &stats_writer.writer;

        try writer.print("Screen: {d}x{d} -> {d}c \n", .{
            screen.size.x,
            screen.size.y,
            screen.buf.len,
        });

        {
            _ = try writer.write("Memory Usage: ");

            _ = try writer.write("Tree-");
            try self.tree_allocator.prettyPrintBytesUsed(writer);
            try writer.writeByte(' ');

            _ = try writer.write("Render-");
            try self.render_allocator.prettyPrintBytesUsed(writer);
            try writer.writeByte(' ');

            try writer.writeByte('\n');
        }

        {
            _ = try writer.write("Memory Capacity: ");

            try writer.print("DrawLoop-{d:.1}kB", .{
                @as(f64, @floatFromInt(self.arena.queryCapacity())) / 1024,
            });
            try writer.writeByte(' ');

            try writer.writeByte('\n');
        }

        _ = try writer.print("Last Frame Time: {d}µs\n", .{self.last_frame_time});

        try writer.flush();
    }

    try self.renderer.render(&self.screen_store, self.tty);

    {
        const flush_trace_zone = tracy.Zone.begin(.{
            .name = "[Engine]: flush to terminal",
            .src = @src(),
        });
        defer flush_trace_zone.end();

        try self.tty.flush();
    }

    const end = std.time.microTimestamp();
    self.last_frame_time = end - start;
}
