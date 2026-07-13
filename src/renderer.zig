const std = @import("std");

const tracy = @import("tracy");
const zttio = @import("zttio");
const ctlseqs = zttio.ctlseqs;

const Screen = @import("screen/screen.zig");
const ScreenStore = @import("screen/screen_store.zig");
const ScreenVec = @import("screen/screen_vec.zig");
const Segment = @import("screen/segment.zig");
const Styling = @import("screen/styling.zig").Styling;
const Tree = @import("tree/tree.zig");
const Unicode = @import("unicode.zig");

const Renderer = @This();

next: *Screen,
prev: *Screen,

redraw: bool = true,

pub fn init(allocator: std.mem.Allocator, screen_store: *ScreenStore, size: ScreenVec, unicode_width_method: Unicode.WidthMethod) std.mem.Allocator.Error!Renderer {
    var first_screen = try allocator.create(Screen);
    first_screen.* = try Screen.init(allocator, screen_store, size, unicode_width_method);
    errdefer first_screen.deinit();

    var second_screen = try allocator.create(Screen);
    second_screen.* = try Screen.init(allocator, screen_store, size, unicode_width_method);
    errdefer second_screen.deinit();

    return Renderer{
        .next = second_screen,
        .prev = first_screen,
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

pub fn prepareNextFrameScreen(self: *Renderer) void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Renderer]: prepare next frame screen",
        .src = @src(),
    });
    defer trace_zone.end();

    self.getScreen().clear();
}

pub fn resize(self: *Renderer, new_size: ScreenVec) std.mem.Allocator.Error!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Renderer]: resize",
        .src = @src(),
    });
    defer trace_zone.end();

    try self.next.resize(new_size);
    try self.prev.resize(new_size);

    self.redraw = true;
}

pub const RenderError = std.mem.Allocator.Error || std.Io.Writer.Error;

pub fn render(self: *Renderer, screen_store: *const ScreenStore, writer: *std.Io.Writer) RenderError!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Renderer]: render",
        .src = @src(),
    });
    defer trace_zone.end();

    try writer.writeAll(ctlseqs.Terminal.sync_begin);

    const next = self.next;

    if (self.redraw) {
        self.redraw = false;
        try renderScreen(next, screen_store, writer);
    } else {
        try renderDiff(self.prev, next, screen_store, writer);
    }

    try writer.writeAll(ctlseqs.Terminal.sync_end);

    self.next = self.prev;
    self.prev = next;
}

fn renderDiff(old_screen: *const Screen, new_screen: *const Screen, store: *const ScreenStore, writer: *std.Io.Writer) RenderError!void {
    std.debug.assert(old_screen.size.eql(new_screen.size));

    const trace_zone = tracy.Zone.begin(.{
        .name = "[Renderer]: render Diff",
        .src = @src(),
    });
    defer trace_zone.end();

    try writer.writeAll(ctlseqs.Cursor.hide ++ ctlseqs.Cursor.home ++ zttio.Styling.reset);

    var next_wrap: usize = new_screen.size.x;
    var old_column: usize = 0;
    var cur_styling: *const Styling = &.{};
    var cur_styling_handle: ScreenStore.StylingHandle = .invalid;
    var cur_segment_handle: ScreenStore.SegmentHandle = .invalid;
    var current_segment: *const Segment = &.{};
    var iter = Screen.ScreenDiffIterator.init(old_screen, new_screen);
    while (iter.next()) |cell_diff| {
        while (cell_diff.idx.value() >= next_wrap) {
            try writer.writeByte('\n');
            next_wrap += new_screen.size.x;
            old_column = 0;
        }
        const cell = cell_diff.cell;

        const new_column = cell_diff.idx.value() - (next_wrap - new_screen.size.x);
        const jumped_cells = new_column - old_column;

        if (!cell.styling.eql(cur_styling_handle)) {
            if (!cell.styling.isInvalid()) {
                const styling = new_screen.store.getStyling(cell.styling);
                if (cur_segment_handle.isInvalid()) {
                    try styling.print(writer);
                } else {
                    const styling_diff = cur_styling.diff(styling);
                    try styling_diff.print(writer);
                }

                cur_styling = styling;
            } else {
                try writer.writeAll(Styling.reset);

                cur_styling = undefined;
            }

            cur_styling_handle = cell.styling;
        }

        if (!cell.segment.eql(cur_segment_handle)) {
            if (!cur_segment_handle.isInvalid()) {
                try current_segment.end(writer);
            }

            if (!cell.segment.isInvalid()) {
                const segment = store.getSegment(cell.segment);
                try segment.begin(writer);
                current_segment = segment;
            }

            cur_segment_handle = cell.segment;
        }

        if (cell.content == .skipped) {
            continue;
        }

        try ctlseqs.Cursor.moveRight(writer, jumped_cells);
        old_column = new_column + 1;

        switch (cell.content) {
            .skipped,
            => unreachable,

            .empty => {
                try writer.writeByte(' ');
            },
            .char => |c| {
                try writer.writeByte(c);
            },
            .short => {
                try writer.writeAll(cell.content.readShort());
            },
            .frame_long => |idx| {
                const str = new_screen.getStr(idx);
                try writer.writeAll(str);
            },
            .shared_long => |handle| {
                const str = store.getStr(handle).*;
                try writer.writeAll(str);
            },
        }
    }

    if (new_screen.cursor_visible) {
        try ctlseqs.Cursor.setCursorShape(writer, new_screen.cursor_shape);
        try ctlseqs.Cursor.moveTo(writer, new_screen.cursor_pos.y + 1, new_screen.cursor_pos.x + 1);
        try writer.writeAll(ctlseqs.Cursor.show);
    }
}

// @TODO: improve rendering with widthmethod: .wcwidth
// fn renderDiff(screen: *const Screen, store: *const ScreenStore, diff: *const Screen.Diff, writer: *std.Io.Writer) RenderError!void {
//     const trace_zone = tracy.Zone.begin(.{
//         .name = "[Renderer]: render Diff",
//         .src = @src(),
//     });
//     defer trace_zone.end();

//     try writer.writeAll(ctlseqs.Cursor.hide ++ ctlseqs.Cursor.home ++ zttio.Styling.reset);

//     var i: usize = 0;
//     var next_wrap: usize = diff.size.x;
//     var jumped_cells: u16 = 0;
//     var cur_style_handle: ScreenStore.StyleHandle = .invalid;
//     var cur_segment_handle: ScreenStore.SegmentHandle = .invalid;
//     var current_segment: *const Segment = undefined;
//     while (i < diff.len()) : (i += 1) {
//         const cell = diff.buf[i];
//         if (i >= next_wrap) {
//             try writer.writeByte('\n');
//             next_wrap += diff.size.x;
//             jumped_cells = 0;
//         }

//         switch (cell.content) {
//             .empty => {
//                 jumped_cells += 1;
//                 continue;
//             },
//             .wide_continuation => {
//                 continue;
//             },
//             else => {
//                 if (jumped_cells > 0) {
//                     try ctlseqs.Cursor.moveRight(writer, jumped_cells);
//                     jumped_cells = 0;
//                 }
//             },
//         }

//         if (!cell.style.eql(cur_style_handle)) {
//             if (cell.style.isInvalid()) {
//                 try writer.writeAll(Style.reset);
//             } else {
//                 const style = store.getStyle(cell.style);
//                 try style.print(writer);
//             }

//             cur_style_handle = cell.style;
//         }

//         if (!cell.segment.eql(cur_segment_handle)) {
//             if (!cur_segment_handle.isInvalid()) {
//                 try current_segment.end(writer);
//             }

//             if (!cell.segment.isInvalid()) {
//                 const segment = store.getSegment(cell.segment);
//                 try segment.begin(writer);
//                 current_segment = segment;
//             }

//             cur_segment_handle = cell.segment;
//         }

//         switch (cell.content) {
//             .empty,
//             .wide_continuation,
//             => unreachable,

//             .char => |c| {
//                 try writer.writeByte(c);
//             },
//             .short => {
//                 try writer.writeAll(cell.content.readShort());
//             },
//             .long_local => |idx| {
//                 const str = screen.getStr(idx);
//                 try writer.writeAll(str);
//             },
//             .long_shared => |handle| {
//                 const str = store.getStr(handle);
//                 try writer.writeAll(str);
//             },
//         }
//     }

//     if (screen.cursor_visible) {
//         try ctlseqs.Cursor.setCursorShape(writer, screen.cursor_shape);
//         try ctlseqs.Cursor.moveTo(writer, screen.cursor_pos.x + 1, screen.cursor_pos.y + 1);
//         try writer.writeAll(ctlseqs.Cursor.show);
//     }
// }

fn renderScreen(screen: *const Screen, store: *const ScreenStore, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Renderer]: render Direct",
        .src = @src(),
    });
    defer trace_zone.end();

    try writer.writeAll(ctlseqs.Cursor.hide ++ ctlseqs.Cursor.home ++ ctlseqs.Erase.scroll_back ++ ctlseqs.Erase.visible_screen ++ Styling.reset);

    var next_wrap: usize = screen.size.x;
    var cur_styling: *const Styling = &.{};
    var cur_styling_handle: ScreenStore.StylingHandle = .invalid;
    var cur_segment_handle: ScreenStore.SegmentHandle = .invalid;
    var cur_segment: *const Segment = &.{};
    var i: usize = 0;
    while (i < screen.len()) : (i += 1) {
        const cell = screen.buf[i];
        if (i >= next_wrap) {
            try writer.writeByte('\n');
            next_wrap += screen.size.x;
        }

        if (cell.content == .skipped) {
            continue;
        }

        if (!cell.styling.eql(cur_styling_handle)) {
            if (!cell.styling.isInvalid()) {
                const styling = screen.store.getStyling(cell.styling);
                if (cur_segment_handle.isInvalid()) {
                    try styling.print(writer);
                } else {
                    const styling_diff = cur_styling.diff(styling);
                    try styling_diff.print(writer);
                }

                cur_styling = styling;
            } else {
                try writer.writeAll(Styling.reset);

                cur_styling = undefined;
            }

            cur_styling_handle = cell.styling;
        }

        if (!cell.segment.eql(cur_segment_handle)) {
            if (!cur_segment_handle.isInvalid()) {
                try cur_segment.end(writer);
            }

            if (!cell.segment.isInvalid()) {
                const segment = store.getSegment(cell.segment);
                try segment.begin(writer);
                cur_segment = segment;
            }

            cur_segment_handle = cell.segment;
        }

        switch (cell.content) {
            .empty => {
                try writer.writeByte(' ');
            },
            .char => |c| {
                try writer.writeByte(c);
            },
            .short => {
                try writer.writeAll(cell.content.readShort());
            },
            .frame_long => |idx| {
                const str = screen.getStr(idx);
                try writer.writeAll(str);
            },
            .shared_long => |handle| {
                const str = store.getStr(handle).*;
                try writer.writeAll(str);
            },
            .skipped => unreachable,
        }
    }

    if (screen.cursor_visible) {
        try ctlseqs.Cursor.setCursorShape(writer, screen.cursor_shape);
        try ctlseqs.Cursor.moveTo(writer, screen.cursor_pos.x + 1, screen.cursor_pos.y + 1);
        try writer.writeAll(ctlseqs.Cursor.show);
    }
}
