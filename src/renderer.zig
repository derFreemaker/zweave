const std = @import("std");
const tracy = @import("tracy");
const zttio = @import("zttio");

const Unicode = @import("common/unicode.zig");
const ScreenVec = @import("common/screen_vec.zig");
const Screen = @import("screen/screen.zig");
const ScreenStore = @import("screen/screen_store.zig");
const Tree = @import("tree/tree.zig");
const Segment = @import("screen/segment.zig");
const Style = @import("screen/styling.zig").Style;

const Renderer = @This();

next: *Screen,
prev: *Screen,

diff: Screen.Diff,

redraw: bool = true,

pub fn init(allocator: std.mem.Allocator, size: ScreenVec, unicode_width_method: Unicode.WidthMethod) std.mem.Allocator.Error!Renderer {
    var first_screen = try allocator.create(Screen);
    first_screen.* = try Screen.init(allocator, size, unicode_width_method);
    errdefer first_screen.deinit();

    var second_screen = try allocator.create(Screen);
    second_screen.* = try Screen.init(allocator, size, unicode_width_method);
    errdefer second_screen.deinit();

    var diff = try Screen.Diff.init(allocator, size);
    errdefer diff.deinit();

    return Renderer{
        .next = second_screen,
        .prev = first_screen,

        .diff = diff,
    };
}

pub fn deinit(self: *Renderer, allocator: std.mem.Allocator) void {
    self.diff.deinit();

    self.prev.deinit();
    allocator.destroy(self.prev);

    self.next.deinit();
    allocator.destroy(self.next);
}

pub inline fn getScreen(self: *const Renderer) *Screen {
    return self.next;
}

pub fn prepareNextFrameScreen(self: *Renderer) *Screen {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Renderer]: prepare next frame screen",
        .src = @src(),
    });
    defer trace_zone.end();

    self.getScreen().clear();
    if (!self.redraw) {
        self.diff.clear();
    }

    return self.getScreen();
}

pub fn resize(self: *Renderer, new_size: ScreenVec) std.mem.Allocator.Error!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Renderer]: resize",
        .src = @src(),
    });
    defer trace_zone.end();

    try self.next.resize(new_size);
    try self.prev.resize(new_size);
    try self.diff.resize(new_size);

    self.redraw = true;
}

pub const RenderError = std.mem.Allocator.Error || std.Io.Writer.Error;

pub fn render(self: *Renderer, screen_store: *const ScreenStore, tty: *zttio.Tty) RenderError!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Renderer]: render",
        .src = @src(),
    });
    defer trace_zone.end();

    tty.startSync() catch {};

    const next = self.next;

    if (self.redraw) {
        self.redraw = false;
        try renderDirect(next, screen_store, tty);
    } else {
        self.prev.diff(next, &self.diff);
        try renderDiff(next, screen_store, &self.diff, tty);
    }

    tty.endSync() catch {};

    self.next = self.prev;
    self.prev = next;
}

fn renderDiff(screen: *const Screen, store: *const ScreenStore, diff: *const Screen.Diff, tty: *zttio.Tty) RenderError!void {
    try tty.hideCursor();
    try tty.moveCursor(.home);
    try tty.stdout.writeAll(zttio.Styling.reset);

    var next_wrap = diff.size.x;
    var cur_style_handle: ScreenStore.StyleHandle = .invalid;
    var cur_segment_handle: ScreenStore.SegmentHandle = .invalid;
    var current_segment: *const Segment = undefined;
    var i: usize = 0;
    var jumped_cells: u16 = 0;
    while (i < diff.len()) : (i += 1) {
        const cell = diff.buf[i];
        if (i >= next_wrap) {
            try tty.stdout.writeByte('\n');
            next_wrap += diff.size.x;
            jumped_cells = 0;
        }

        switch (cell.content) {
            .empty => {
                jumped_cells += 1;
                continue;
            },
            .wide_continuation => {
                continue;
            },
            else => {
                try tty.moveCursor(.{ .right = jumped_cells });
                jumped_cells = 0;
            },
        }

        if (!cell.style.eql(cur_style_handle)) {
            if (cell.style.isInvalid()) {
                try tty.setStyling(&Style{});
            } else {
                const style = store.getStyle(cell.style);
                try tty.setStyling(style);
            }

            cur_style_handle = cell.style;
        }

        if (!cell.segment.eql(cur_segment_handle)) {
            if (!cur_segment_handle.isInvalid()) {
                try current_segment.end(tty.stdout);
            }

            if (!cell.segment.isInvalid()) {
                const segment = store.getSegment(cell.segment);
                try segment.begin(tty.stdout);
                current_segment = segment;
            }

            cur_segment_handle = cell.segment;
        }

        switch (cell.content) {
            .empty,
            .wide_continuation,
            => unreachable,

            .char => |c| {
                try tty.stdout.writeByte(c);
            },
            .short => {
                try tty.stdout.writeAll(cell.content.readShort());
            },
            .long_local => |idx| {
                const str = screen.getStr(idx);
                try tty.stdout.writeAll(str);
            },
            .long_shared => |handle| {
                const str = store.getStr(handle);
                try tty.stdout.writeAll(str);
            },
        }
    }

    if (screen.cursor_visible) {
        try tty.setCursorShape(screen.cursor_shape);
        try tty.moveCursor(.{ .pos = .{
            .row = screen.cursor_pos.x + 1,
            .column = screen.cursor_pos.y + 1,
        } });
        try tty.showCursor();
    }
}

fn renderDirect(screen: *const Screen, store: *const ScreenStore, tty: *zttio.Tty) std.Io.Writer.Error!void {
    try tty.clearScreen(.entire);
    try tty.hideCursor();
    try tty.moveCursor(.home);

    var next_wrap: usize = screen.size.x;
    var current_style_handle: ScreenStore.StyleHandle = .invalid;
    var current_segment_handle: ScreenStore.SegmentHandle = .invalid;
    var current_segment: *const Segment = undefined;
    var i: usize = 0;
    while (i < screen.len()) : (i += 1) {
        const cell = screen.buf[i];
        if (i >= next_wrap) {
            try tty.stdout.writeByte('\n');
            next_wrap += screen.size.x;
        }

        if (cell.content == .wide_continuation) {
            continue;
        }

        if (!cell.style.eql(current_style_handle)) {
            if (cell.style.isInvalid()) {
                try tty.setStyling(&Style{});
            } else {
                const style = store.getStyle(cell.style);
                try tty.setStyling(style);
            }

            current_style_handle = cell.style;
        }

        if (!cell.segment.eql(current_segment_handle)) {
            if (!current_segment_handle.isInvalid()) {
                try current_segment.end(tty.stdout);
            }

            if (!cell.segment.isInvalid()) {
                const segment = store.getSegment(cell.segment);
                try segment.begin(tty.stdout);
                current_segment = segment;
            }

            current_segment_handle = cell.segment;
        }

        switch (cell.content) {
            .empty => {
                try tty.stdout.writeByte(' ');
            },
            .char => |c| {
                try tty.stdout.writeByte(c);
            },
            .short => {
                try tty.stdout.writeAll(cell.content.readShort());
            },
            .long_local => |idx| {
                const str = screen.getStr(idx);
                try tty.stdout.writeAll(str);
            },
            .long_shared => |handle| {
                const str = store.getStr(handle);
                try tty.stdout.writeAll(str);
            },
            .wide_continuation => unreachable,
        }
    }

    if (screen.cursor_visible) {
        try tty.setCursorShape(screen.cursor_shape);
        try tty.moveCursor(.{ .pos = .{
            .row = screen.cursor_pos.x + 1,
            .column = screen.cursor_pos.y + 1,
        } });
        try tty.showCursor();
    }
}
