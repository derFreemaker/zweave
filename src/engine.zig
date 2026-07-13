const std = @import("std");
pub const InitError = std.mem.Allocator.Error;
pub const LayoutError = std.mem.Allocator.Error;

const tracy = @import("tracy");

const CountingAllocator = @import("common/counting_allocator.zig");
const Event = @import("event.zig").Event;
const Renderer = @import("renderer.zig");
const Screen = @import("screen/screen.zig");
const ScreenStore = @import("screen/screen_store.zig");
const ScreenVec = @import("screen/screen_vec.zig");
const Styling = @import("screen/styling.zig").Styling;
const Element = @import("tree/element.zig");
const Tree = @import("tree/tree.zig");
const Unicode = @import("unicode.zig");
const Container = @import("widgets/container.zig");

const Engine = @This();

allocator: std.mem.Allocator,
tree_allocator: CountingAllocator,
render_allocator: CountingAllocator,
arena: std.heap.ArenaAllocator,

writer: *std.Io.Writer,
width_method: Unicode.WidthMethod,

tree: Tree,
screen_store: ScreenStore,
renderer: Renderer,

root_container: Container,
root: Element.Handle,

last_mouse_pos: ?ScreenVec,

show_stats: bool,
show_debug_tree: bool,
debug_styling: ScreenStore.StylingHandle,

prev_frame_render_time: std.Io.Duration,
prev_frame_flush_time: std.Io.Duration,

pub fn init(allocator: std.mem.Allocator, writer: *std.Io.Writer, width_method: Unicode.WidthMethod, screen_size: ScreenVec) InitError!*Engine {
    const ptr = try allocator.create(Engine);
    errdefer allocator.destroy(ptr);

    ptr.allocator = allocator;
    ptr.tree_allocator = CountingAllocator.init(allocator);
    ptr.render_allocator = CountingAllocator.init(allocator);
    ptr.arena = std.heap.ArenaAllocator.init(allocator);

    ptr.writer = writer;
    ptr.width_method = width_method;
    ptr.tree = try Tree.init(ptr.tree_allocator.allocator());
    errdefer ptr.tree.deinit();

    ptr.screen_store = try ScreenStore.init(ptr.render_allocator.allocator());
    errdefer ptr.screen_store.deinit();

    ptr.renderer = try Renderer.init(ptr.render_allocator.allocator(), &ptr.screen_store, screen_size, ptr.width_method);
    errdefer ptr.renderer.deinit(allocator);

    ptr.root_container = Container{};
    ptr.root = try ptr.tree.create(ptr.root_container.element());
    errdefer ptr.tree.destroy(ptr.root);

    ptr.last_mouse_pos = null;

    ptr.show_stats = false;
    ptr.show_debug_tree = false;
    ptr.debug_styling = try ptr.screen_store.addStyling(Styling{
        .bg = .{ .c8 = .black },
        .fg = .{ .c8 = .bright_green },
    });
    errdefer ptr.screen_store.removeStyling(ptr.debug_styling);

    ptr.prev_frame_render_time = .zero;
    ptr.prev_frame_flush_time = .zero;

    return ptr;
}

pub fn deinit(self: *Engine) void {
    self.writer.flush() catch {};

    self.arena.deinit();

    self.renderer.deinit(self.render_allocator.allocator());
    self.screen_store.deinit();
    self.tree.deinit();

    self.allocator.destroy(self);
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

    switch (event.*) {
        .mouse => |mouse| {
            self.last_mouse_pos = ScreenVec{ .x = mouse.col, .y = mouse.row };
        },
        else => {},
    }

    var consumed = false;
    var ctx = Element.OnEventContext{
        .tree = &self.tree,

        .event = event,
        .consumed = &consumed,

        .mouse_rel_pos = switch (event.*) {
            .mouse => |mouse| ScreenVec{ .x = mouse.col, .y = mouse.row },
            else => null,
        },
    };
    try root.interface.onEvent(&ctx);
}

fn computeLayout(self: *Engine, allocator: std.mem.Allocator, screen: *Screen, root: *const Element) LayoutError!ScreenVec {
    const layout_trace_zone = tracy.Zone.begin(.{
        .name = "[Engine]: layout",
        .src = @src(),
    });
    defer layout_trace_zone.end();

    const ctx = Element.ComputeLayoutContext{
        .allocator = allocator,
        .tree = &self.tree,
        .screen_store = &self.screen_store,

        .width_method = screen.width_method,

        .viewport_size = screen.size,
        .parent_size = screen.size,
        .available = screen.size,
    };
    const needed_space = try root.interface.computeLayout(&ctx);

    return needed_space;
}

pub fn renderNextFrame(self: *Engine, io: std.Io) Renderer.RenderError!void {
    {
        const trace_zone = tracy.Zone.begin(.{
            .name = "[Engine]: renderNextFrame",
            .src = @src(),
        });
        defer trace_zone.end();

        const start_render = std.Io.Timestamp.now(io, .real);

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
                .size = needed_space,
            });

            const ctx = Element.DrawContext{
                .tree = &self.tree,

                .view = root_view,
                .screen_store = &self.screen_store,

                .mouse_rel_pos = self.last_mouse_pos,
            };
            try root.interface.draw(&ctx);
        }

        if (self.show_stats) {
            try self.writeStats();
        }

        if (self.show_debug_tree) {
            try self.writeDebugTree();
        }

        try self.renderer.render(&self.screen_store, self.writer);

        const end_render = std.Io.Timestamp.now(io, .real);
        self.prev_frame_render_time = start_render.durationTo(end_render);

        var buf: [128]u8 = undefined;
        tracy.message(.{ .text = std.fmt.bufPrint(&buf, "render_frame_time: {f}", .{self.prev_frame_render_time}) catch unreachable });
    }

    {
        const start_flush = std.Io.Timestamp.now(io, .real);

        const flush_trace_zone = tracy.Zone.begin(.{
            .name = "[Engine]: flush to terminal",
            .src = @src(),
        });
        defer flush_trace_zone.end();

        try self.writer.flush();

        const end_flush = std.Io.Timestamp.now(io, .real);
        self.prev_frame_flush_time = start_flush.durationTo(end_flush);
    }
}

fn writeStats(self: *const Engine) std.Io.Writer.Error!void {
    const stats_trace_zone = tracy.Zone.begin(.{
        .name = "[Engine]: stats write",
        .src = @src(),
    });
    defer stats_trace_zone.end();

    const screen = self.renderer.getScreen();

    const stats_view = screen.view(.{});

    var stats_buf: [256]u8 = undefined;
    var stats_writer = stats_view.writer(&stats_buf, .{
        .styling = self.debug_styling,
    });
    const writer = &stats_writer.interface;

    tracy.message(.{ .text = std.fmt.bufPrint(&stats_buf, "Screen: {d}x{d} cells: {d}c", .{ screen.size.x, screen.size.y, screen.len() }) catch unreachable });

    try writer.print("Screen: {d}x{d} -> {d}c cap: {d}c\n", .{
        screen.size.x,
        screen.size.y,
        @as(u32, screen.size.x * screen.size.y),
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

    _ = try writer.print("prev Frame Time: {f} (engine) - {f} (flush)\n", .{ self.prev_frame_render_time, self.prev_frame_flush_time });

    try writer.flush();
}

fn writeDebugTree(self: *const Engine) std.Io.Writer.Error!void {
    const stats_trace_zone = tracy.Zone.begin(.{
        .name = "[Engine]: write debug tree",
        .src = @src(),
    });
    defer stats_trace_zone.end();

    const screen = self.renderer.getScreen();

    const stats_view = screen.view(.{});

    var stats_buf: [256]u8 = undefined;
    var stats_writer = stats_view.writer(&stats_buf, .{
        .styling = self.debug_styling,
    });
    const writer = &stats_writer.interface;

    try writer.print("{f} ", .{self.root});
    try writer.writeAll("<root>\n");
    try self.tree.writeDebugElementTree(writer, self.root, 1);

    try writer.flush();
}
