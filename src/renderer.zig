const std = @import("std");
const tracy = @import("tracy");
const zttio = @import("zttio");

const Screen = @import("screen/screen.zig");
const ScreenStore = @import("screen/screen_store.zig");
const Tree = @import("tree/tree.zig");
const Segment = @import("screen/segment.zig");
const Style = @import("screen/styling.zig").Style;

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
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Renderer]: resize",
        .src = @src(),
    });
    defer trace_zone.end();

    try self.next.resize(new_winsize);
    try self.prev.resize(new_winsize);
}

pub fn render(self: *Renderer, screen_store: *const ScreenStore, tty: *zttio.Tty) error{UnableToRender}!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Renderer]: render",
        .src = @src(),
    });
    defer trace_zone.end();

    tty.startSync() catch {};

    const next = self.next;
    renderDirect(next, screen_store, tty) catch return error.UnableToRender;

    tty.endSync() catch {};

    self.next = self.prev;
    self.prev = next;
}

fn renderDirect(screen: *const Screen, store: *const ScreenStore, tty: *zttio.Tty) std.Io.Writer.Error!void {
    try tty.clearScreen(.entire);
    try tty.hideCursor();
    try tty.moveCursor(.home);

    var next_wrap: usize = screen.winsize.cols;
    var current_style_handle: ScreenStore.StyleHandle = .invalid;
    var current_segment_handle: ScreenStore.SegmentHandle = .invalid;
    var current_segment: *const Segment = undefined;
    var i: usize = 0;
    while (i < screen.len()) : (i += 1) {
        const cell = screen.buf[i];
        if (i >= next_wrap) {
            try tty.stdout.writeByte('\n');
            next_wrap += screen.winsize.cols;
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
            .short => |s| {
                const end = std.mem.indexOf(u8, &s, &.{0}) orelse 11;
                try tty.stdout.writeAll(s[0..end]);
            },
            .long_local => |index| {
                const str = screen.strs.items[index.value()];
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
