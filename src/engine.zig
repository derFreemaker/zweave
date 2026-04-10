const std = @import("std");
const tracy = @import("tracy");
const zttio = @import("zttio");

const ScreenVec = @import("common/screen_vec.zig");
const CountingAllocator = @import("common/counting_allocator.zig");
const Container = @import("widgets/container.zig");
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

adapter: zttio.Adapters.NativeAdapter,
parser: zttio.Parsers.NormalParser,
tty: zttio.Tty,
tree: Tree,
screen_store: ScreenStore,
renderer: Renderer,

root_container: Container,
root: Element.Handle,

stats_style: ScreenStore.StyleHandle,
show_stats: bool,
show_debug_tree: bool,

prev_frame_render_time: i64,
prev_frame_flush_time: i64,

pub const InitError = error{UnableToInitTty} || std.mem.Allocator.Error;

pub fn init_(self: *Engine, allocator: std.mem.Allocator, event_allocator: std.mem.Allocator) InitError!void {
    self.allocator = allocator;
    self.tree_allocator = CountingAllocator.init(allocator);
    self.render_allocator = CountingAllocator.init(allocator);
    self.arena = std.heap.ArenaAllocator.init(allocator);

    self.adapter = zttio.Adapters.NativeAdapter.init(allocator, .stdin(), .stdout()) catch return error.UnableToInitTty;
    self.parser = zttio.Parsers.NormalParser.init(allocator, event_allocator, self.adapter.adapter());
    self.tty = zttio.Tty.init(
        allocator,
        self.parser.parser(),
        .{
            .caps = zttio.TerminalCapabilities.query(self.adapter.adapter(), 100) catch return error.UnableToInitTty,
        },
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

    self.root_container = Container{
        .gap = .{
            .x = 2,
            .y = 1,
        },
    };
    self.root = try self.tree.create(self.root_container.element());
    errdefer self.tree.destroy(self.root);

    self.stats_style = try self.screen_store.addStyle(Style{
        .background = .{ .c8 = .black },
        .foreground = .{ .c8 = .bright_green },
    });
    errdefer self.screen_store.removeStyle(self.stats_style);
    self.show_stats = false;
    self.show_debug_tree = false;

    self.prev_frame_render_time = 0;
    self.prev_frame_flush_time = 0;
}

pub fn deinit(self: *Engine) void {
    self.arena.deinit();

    self.renderer.deinit(self.render_allocator.allocator());
    self.screen_store.deinit();
    self.tree.deinit();

    self.tty.deinit();
    self.parser.deinit();
    self.adapter.deinit(self.allocator);
}

pub inline fn resize(self: *Engine, new_size: ScreenVec) std.mem.Allocator.Error!void {
    return self.renderer.resize(new_size);
}

/// if `value` is `null`, it toggles
pub fn showStats(self: *Engine, value: ?bool) void {
    if (value) |v| {
        self.show_stats = v;
    } else {
        self.show_stats = !self.show_stats;
    }
}

/// if `value` is `null`, it toggles
pub fn showDebugTree(self: *Engine, value: ?bool) void {
    if (value) |v| {
        self.show_debug_tree = v;
    } else {
        self.show_debug_tree = !self.show_debug_tree;
    }
}

pub fn dispatchEvent(self: *Engine, event: *const Event) std.mem.Allocator.Error!void {
    const root = self.tree.get(self.root);

    var ctx = Element.OnEventContext{
        .tree = &self.tree,

        .event = event,
    };
    try root.interface.onEvent(&ctx);
}

pub fn dispatchEventToFocusedElement(self: *Engine, event: *const Event) std.mem.Allocator.Error!void {
    if (self.tree.isFocused(.invalid)) return;
    const handle = self.tree.focused_element;
    const element = self.tree.get(handle);

    var ctx = Element.OnEventContext{
        .tree = &self.tree,

        .event = event,
    };
    try element.interface.onEvent(&ctx);
}

pub const LayoutError = std.mem.Allocator.Error;

fn computeLayout(self: *Engine, allocator: std.mem.Allocator, screen: *Screen, root: *const Element) LayoutError!ScreenVec {
    const layout_trace_zone = tracy.Zone.begin(.{
        .name = "[Engine]: layout",
        .src = @src(),
    });
    defer layout_trace_zone.end();

    const ctx = Element.ComputeLayoutContext{
        .allocator = allocator,
        .tree = &self.tree,

        .width_method = screen.width_method,

        .viewport_size = screen.size,
        .parent_size = screen.size,
        .available = screen.size,
    };
    const needed_space = try root.interface.computeLayout(&ctx);

    return needed_space;
}

pub fn renderNextFrame(self: *Engine) Renderer.RenderError!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Engine]: renderNextFrame",
        .src = @src(),
    });
    defer trace_zone.end();

    const start_render = std.time.microTimestamp();

    _ = self.arena.reset(.{ .retain_with_limit = 8 * 1024 * 1024 });
    var trace_allocator = tracy.Allocator{
        .pool_name = "[Engine]: FrameArena",
        .parent = self.arena.allocator(),
    };
    const allocator = trace_allocator.allocator();

    self.renderer.prepareNextFrameScreen();
    var screen = self.renderer.getScreen();

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

        const ctx = Element.DrawContext{
            .tree = &self.tree,

            .view = root_view,
            .screen_store = &self.screen_store,
        };
        try root.interface.draw(&ctx);
    }

    if (self.show_stats) {
        try self.writeStats();
    }

    if (self.show_debug_tree) {
        try self.writeDebugTree();
    }

    try self.renderer.render(&self.screen_store, &self.tty);

    const end_render = std.time.microTimestamp();
    self.prev_frame_render_time = end_render - start_render;

    {
        const start_flush = std.time.microTimestamp();

        const flush_trace_zone = tracy.Zone.begin(.{
            .name = "[Engine]: flush to terminal",
            .src = @src(),
        });
        defer flush_trace_zone.end();

        try self.tty.flush();

        const end_flush = std.time.microTimestamp();
        self.prev_frame_flush_time = end_flush - start_flush;
    }
}

fn writeStats(self: *const Engine) std.Io.Writer.Error!void {
    const stats_trace_zone = tracy.Zone.begin(.{
        .name = "[Engine]: stats write",
        .src = @src(),
    });
    defer stats_trace_zone.end();

    const screen = self.renderer.getScreen();

    const stats_view = screen.view(.{
        .col = 0,
        .row = 0,

        .default_style = self.stats_style,
    });

    var stats_buf: [128]u8 = undefined;
    var stats_writer = stats_view.writer(&stats_buf);
    const writer = &stats_writer.writer;

    try writer.print("Screen: {d}x{d} -> {d}c\n", .{
        screen.size.x,
        screen.size.y,
        screen.buf.len,
    });

    {
        _ = try writer.write("Memory Usage:");

        _ = try writer.write(" Tree-");
        try self.tree_allocator.prettyPrintBytesUsed(writer);

        _ = try writer.write(" Render-");
        try self.render_allocator.prettyPrintBytesUsed(writer);

        try writer.writeByte('\n');
    }

    {
        _ = try writer.write("Memory Capacity:");

        try writer.print(" DrawLoop-{d:.1}kB", .{
            @as(f64, @floatFromInt(self.arena.queryCapacity())) / 1024,
        });

        try writer.writeByte('\n');
    }

    _ = try writer.print("prev Frame Time: {d}µs - {d}µs\n", .{ self.prev_frame_render_time, self.prev_frame_flush_time });

    try writer.print("caps: {any}\n", .{self.tty.caps});

    try writer.flush();
}

fn writeDebugTree(self: *const Engine) std.Io.Writer.Error!void {
    const stats_trace_zone = tracy.Zone.begin(.{
        .name = "[Engine]: write debug tree",
        .src = @src(),
    });
    defer stats_trace_zone.end();

    const screen = self.renderer.getScreen();

    const stats_view = screen.view(.{
        .col = 0,
        .row = 0,

        .default_style = self.stats_style,
    });

    var stats_buf: [128]u8 = undefined;
    var stats_writer = stats_view.writer(&stats_buf);
    const writer = &stats_writer.writer;

    try writer.print("{f} ", .{self.root});
    try writer.writeAll("<root>\n");
    try self.tree.writeDebugElementTree(writer, self.root, 1);

    try writer.flush();
}
