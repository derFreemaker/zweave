const std = @import("std");
const builtin = @import("builtin");
const tracy = @import("tracy");
const zttio = @import("zttio");

const LineIterator = @import("../common/line_iterator.zig");
const ScreenVec = @import("../common/screen_vec.zig");
const Cell = @import("cell.zig");
const Screen = @import("screen.zig");
const ScreenStore = @import("screen_store.zig");

pub const View = @This();

screen: *Screen,

pos: ScreenVec,
size: ScreenVec,

default_style: ScreenStore.StyleHandle,

pub inline fn strWidth(self: *const View, str: []const u8) usize {
    return self.screen.strWidth(str);
}

/// asserts that you are reading inside the view
pub inline fn readCell(self: *const View, row: u16, col: u16) Cell {
    std.debug.assert(row < self.size.y);
    std.debug.assert(col < self.size.x);

    return self.screen.readCell(self.pos.x + col, self.pos.y + row);
}

/// asserts that you are inside the view
pub fn getCellIndex(self: *const View, row: u16, col: u16) Cell.Index {
    std.debug.assert(row < self.size.y);
    std.debug.assert(col < self.size.x);

    return self.screen.getCellIndex(self.pos.y + row, self.pos.x + col);
}

/// `cell_idx` is the cell which is going to be overriden.
fn correctCellsFront(self: *const View, cell_idx: Cell.Index) void {
    if (cell_idx.value() <= 0) return;

    // If the cell we are going to override is not a 'wide_continuation' than do nothing.
    if (self.screen.buf[cell_idx.value()].content != .wide_continuation) return;

    const inlined_loops = 3;
    // we start at 1 since '0' would be the cell which gets overriden anyway.
    inline for (1..inlined_loops) |i| {
        if (cell_idx.value() - i < 0) return;

        const cell: *Cell = &self.screen.buf[cell_idx.value() - i];
        if (cell.content != .wide_continuation) {
            cell.content = .empty;
            return;
        }

        cell.content = .empty;
    }

    var i: usize = cell_idx.value() - inlined_loops + 1;
    while (i > 0) : (i -= 1) {
        const cell: *Cell = &self.screen.buf[i - 1];
        if (cell.content != .wide_continuation) {
            cell.content = .empty;
            return;
        }

        cell.content = .empty;
    }
}

/// `cell_idx` is the cell behind the now overriden cell.
fn correctCellsEnd(self: *const View, cell_idx: Cell.Index) void {
    const buf_len = self.screen.len();

    const inlined_loops = 3;
    inline for (0..inlined_loops) |i| {
        if (cell_idx.value() + i >= buf_len) return;

        const cell: *Cell = &self.screen.buf[cell_idx.value() + i];
        if (cell.content != .wide_continuation) {
            return;
        }

        cell.content = .empty;
    }

    for (inlined_loops..buf_len) |i| {
        const cell: *Cell = &self.screen.buf[cell_idx.value() + i];
        if (cell.content != .wide_continuation) {
            return;
        }

        cell.content = .empty;
    }
}

pub const WriteCellOptions = struct {
    max_width: ?u16 = null,

    style: ScreenStore.StyleHandle = .invalid,
    segment: ScreenStore.SegmentHandle = .invalid,
};

/// 'store' only needs to be provided if a 'long_shared' content is given.
pub fn writeCell(self: *const View, store: ?*const ScreenStore, row: u16, col: u16, content: Cell.Content, opts: WriteCellOptions) u16 {
    if (row >= self.size.y or col >= self.size.x) {
        return 0;
    }

    const screen = self.screen;
    std.debug.assert(self.pos.y + row < screen.size.y);
    std.debug.assert(self.pos.x + col < screen.size.x);

    const width: u16 = content.calcWidth(screen, store);
    const cell_idx = self.getCellIndex(row, col);
    if (opts.max_width) |max_width| {
        if (width > max_width) {
            @memset(screen.buf[cell_idx.value() .. cell_idx.value() + max_width], Cell{
                .content = .empty,

                .style = opts.style,
                .segment = opts.segment,
            });

            return max_width;
        }
    }
    if (self.pos.x + col + width > screen.size.x) {
        const remaining_width = screen.size.x - self.pos.x + col;
        @memset(screen.buf[cell_idx.value() .. cell_idx.value() + remaining_width], Cell{
            .content = .empty,

            .style = opts.style,
            .segment = opts.segment,
        });

        return remaining_width;
    }

    @call(if (builtin.mode != .Debug) .always_inline else .auto, correctCellsFront, .{ self, cell_idx });

    screen.buf[cell_idx.value()] = .{
        .content = content,

        .style = if (opts.style.isInvalid()) self.default_style else opts.style,
        .segment = opts.segment,
    };

    @memset(screen.buf[cell_idx.value() + 1 .. cell_idx.value() + width], Cell{
        .content = .wide_continuation,

        .style = opts.style,
        .segment = opts.segment,
    });

    @call(if (builtin.mode != .Debug) .always_inline else .auto, correctCellsEnd, .{ self, cell_idx.inc(width) });

    return width;
}

pub const FillOptions = struct {
    style: ScreenStore.StyleHandle = .invalid,
    segment: ScreenStore.SegmentHandle = .invalid,
};

/// 'store' only needs to be provided if a 'long_shared' content is given.
pub fn fill(self: *const View, store: ?*const ScreenStore, row: u16, col: u16, height: u16, width: u16, content: Cell.Content, opts: FillOptions) void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[ScreenView]: fill",
        .src = @src(),
    });
    defer trace_zone.end();

    if (row >= self.size.y or col >= self.size.x) {
        return;
    }

    const safe_height: u16 = @min(self.size.y - row, height);
    const safe_width: u16 = @min(self.size.x - col, width);

    const screen = self.screen;
    std.debug.assert(self.pos.y + row < screen.size.y);
    std.debug.assert(self.pos.y + row + safe_height - 1 < screen.size.y);
    std.debug.assert(self.pos.x + col < screen.size.x);
    std.debug.assert(self.pos.x + col + safe_width - 1 < screen.size.x);

    const cells = @max(content.calcWidth(screen, store), 1);
    if (cells == 1) {
        for (0..safe_height) |h| {
            const start_idx = self.getCellIndex(@intCast(row + h), col);
            const end_idx = start_idx.inc(safe_width);
            @memset(screen.buf[start_idx.value()..end_idx.value()], Cell{
                .content = content,

                .style = opts.style,
                .segment = opts.segment,
            });
        }

        return;
    }

    const amount = std.math.divFloor(u16, safe_width, cells) catch unreachable;
    const remainder = std.math.mod(u16, safe_width, cells) catch unreachable;

    std.debug.assert(cells <= 16);
    var fill_buf: [16]Cell = undefined;
    const fill_view: []Cell = fill_buf[0..cells];
    fill_buf[0] = Cell{
        .content = content,

        .style = opts.style,
        .segment = opts.segment,
    };
    @memset(fill_view[1..], Cell{
        .content = .wide_continuation,

        .style = opts.style,
        .segment = opts.segment,
    });

    for (0..safe_height) |h| {
        const row_idx = self.getCellIndex(@intCast(row + h), col);

        @call(if (builtin.mode != .Debug) .always_inline else .auto, correctCellsFront, .{ self, row_idx });

        var current_col_idx = row_idx;
        for (0..amount) |_| {
            const end_idx = current_col_idx.inc(cells);
            @memcpy(screen.buf[current_col_idx.value()..end_idx.value()], fill_view);

            current_col_idx = current_col_idx.inc(cells);
        }

        const end_idx = current_col_idx.inc(remainder);
        @memset(screen.buf[current_col_idx.value()..end_idx.value()], Cell{
            .content = .{ .char = ' ' },

            .style = opts.style,
            .segment = opts.segment,
        });

        @call(if (builtin.mode != .Debug) .always_inline else .auto, correctCellsEnd, .{ self, row_idx.inc(safe_width) });
    }
}

pub const WriteOptions = struct {
    max_width: ?u16 = null,
    max_height: ?u16 = null,

    style: ScreenStore.StyleHandle = .invalid,
    segment: ScreenStore.SegmentHandle = .invalid,
};

/// Only allocates if a grapheme cluster is bigger than `Cell.CONTENT_SHORT_STR_MAX_LENGTH`.
pub fn write(self: *const View, row: u16, col: u16, content: []const u8, opts: WriteOptions) std.mem.Allocator.Error!ScreenVec {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[ScreenView]: write",
        .src = @src(),
    });
    defer trace_zone.end();

    if (row >= self.size.y or col >= self.size.x) {
        return .zero;
    }

    const screen = self.screen;

    std.debug.assert(self.pos.y + row < screen.size.y);
    std.debug.assert(self.pos.x + col < screen.size.x);

    if (opts.max_height != null and opts.max_height == 0) {
        return .zero;
    }
    if (opts.max_width != null and opts.max_width == 0) {
        return .zero;
    }

    const max_width = if (opts.max_width) |max_width| @min(self.size.x - col, max_width) else self.size.x - col;
    const max_height = if (opts.max_height) |max_height| @min(self.size.y - row, max_height) else self.size.y - row;

    const Unicode = @import("../common/unicode.zig");

    var cur_col: u16 = 0;
    var cur_row: u16 = 0;
    var grapheme_cluster_iter = Unicode.GraphemeClusterIterator.init(content);
    while (grapheme_cluster_iter.next()) |grapheme_cluster| {
        const str = grapheme_cluster.bytes(&grapheme_cluster_iter);

        var cell_content: Cell.Content = undefined;
        switch (str.len) {
            0 => cell_content = .wide_continuation,
            1 => {
                const c = str[0];
                newline: switch (c) {
                    '\r' => {
                        if (grapheme_cluster.start + 1 < content.len and content[grapheme_cluster.start + 1] == '\n') {
                            grapheme_cluster_iter.skip();
                        }

                        continue :newline '\n';
                    },
                    '\n' => {
                        if (cur_row + 1 >= max_height) {
                            return ScreenVec{ .x = cur_row + 1, .y = cur_col };
                        }

                        cur_col = 0;
                        cur_row += 1;
                        continue;
                    },
                    else => {},
                }

                if (cur_col >= max_width) {
                    continue;
                }

                cell_content = .{ .char = c };
            },

            2...Cell.CONTENT_SHORT_STR_MAX_LENGTH => {
                const str_width = self.strWidth(str);
                if (cur_col + str_width > max_width) {
                    continue;
                }

                cell_content = .{ .short = undefined };
                @memcpy(cell_content.short[0..str.len], str);
                if (str.len < Cell.CONTENT_SHORT_STR_MAX_LENGTH) {
                    cell_content.short[str.len] = 0;
                }
            },

            else => {
                const str_width = self.strWidth(str);
                if (cur_col + str_width > max_width) {
                    continue;
                }

                const idx = try screen.addStr(str);
                cell_content = .{ .long_local = idx };
            },
        }

        cur_col += self.writeCell(null, row + cur_row, col + cur_col, cell_content, .{
            .max_width = max_width - cur_col,

            .style = opts.style,
            .segment = opts.segment,
        });
    }

    return ScreenVec{
        .x = cur_col,
        .y = cur_row,
    };
}

/// projects `other_view` onto this view
pub fn projectView(self: *const View, other_view: *const View, row: u16, col: u16) std.mem.Allocator.Error!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[ScreenView]: projectView",
        .src = @src(),
    });
    defer trace_zone.end();

    if (row >= self.size.y or col >= self.size.x) {
        return;
    }

    const screen = self.screen;

    const safe_height = @min(self.size.y - row, other_view.size.y);
    const safe_width = @min(self.size.x - col, other_view.size.x);

    for (0..safe_height) |h| {
        const self_start_idx = self.getCellIndex(row + @as(u16, @intCast(h)), col);
        const self_end_idx = self.getCellIndex(row + @as(u16, @intCast(h)), col + safe_width - 1);
        const self_buf = self.screen.buf[self_start_idx.value() .. self_end_idx.value() + 1];

        const other_start_idx = other_view.getCellIndex(@intCast(h), 0);
        const other_end_idx = other_view.getCellIndex(@intCast(h), safe_width - 1);
        const other_buf = other_view.screen.buf[other_start_idx.value() .. other_end_idx.value() + 1];

        std.debug.assert(self_buf.len == other_buf.len);

        for (0..other_buf.len) |i| {
            self_buf[i] = other_buf[i];

            if (other_buf[i].content == .long_local) {
                const other_long_idx = other_buf[i].content.long_local;

                const self_long_idx = try screen.addStr(other_view.screen.getStr(other_long_idx));
                self_buf[i].content = .{ .long_local = self_long_idx };
            }
        }
    }
}

pub fn writer(self: *const View, buffer: []u8) ViewWriter {
    return ViewWriter.init(self, buffer);
}

pub const Options = struct {
    col: u16 = 0,
    row: u16 = 0,
    width: ?u16 = null,
    height: ?u16 = null,

    default_style: ScreenStore.StyleHandle = .invalid,
};

pub fn view(self: *const View, opts: Options) View {
    var w = opts.width orelse self.size.x - opts.col;
    if (opts.col + w > self.size.x) {
        w = self.size.x - @min(self.size.x, opts.col);
    }

    var h = opts.height orelse self.size.y - opts.row;
    if (opts.row + h > self.size.y) {
        h = self.size.y - @min(self.size.y, opts.row);
    }

    return View{
        .screen = self.screen,

        .pos = .{
            .x = self.pos.x + opts.col,
            .y = self.pos.y + opts.row,
        },
        .size = .{
            .x = w,
            .y = h,
        },

        .default_style = opts.default_style,
    };
}

pub inline fn setCursorPos(self: *const View, pos: ScreenVec) void {
    self.screen.cursor_pos = .{
        .x = self.pos.y + pos.y,
        .y = self.pos.x + pos.x,
    };
}

pub inline fn setCursorShape(self: *const View, shape: Screen.CursorShape) void {
    self.screen.cursor_shape = shape;
}

pub inline fn setCursorVisibility(self: *const View, visible: bool) void {
    self.screen.cursor_visible = visible;
}

pub const ViewWriter = struct {
    view: View,
    writer: std.Io.Writer,

    pos: ScreenVec = .zero,

    pub fn init(view_ptr: *const View, buffer: []u8) ViewWriter {
        return ViewWriter{
            .view = view_ptr.*,
            .writer = std.Io.Writer{
                .buffer = buffer,
                .vtable = &std.Io.Writer.VTable{
                    .drain = drain,
                },
            },
        };
    }

    fn write(self: *ViewWriter, content: []const u8) std.Io.Writer.Error!void {
        var line_iter = LineIterator.init(content);
        while (line_iter.peek()) |line| : (line_iter.toss(line)) {
            const end_pos = self.view.write(self.pos.y, self.pos.x, line.content(&line_iter), .{}) catch return error.WriteFailed;
            self.pos.x += end_pos.x;

            if (line.hasSeparator()) {
                self.pos.x = 0;
                self.pos.y += 1;
            }
        }
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *ViewWriter = @fieldParentPtr("writer", w);

        if (w.end > 0) {
            try self.write(w.buffer[0..w.end]);
            w.end = 0;
        }

        var bytes_written: usize = 0;
        for (data, 0..) |chunk, i| {
            if (i + 1 == data.len and splat < 0) {
                continue;
            }

            try self.write(chunk);
            bytes_written += chunk.len;
            bytes_written += chunk.len;
        }

        if (splat > 1) {
            const chunk = data[data.len - 1];
            for (0..splat - 1) |_| {
                try self.write(chunk);
                bytes_written += chunk.len;
            }
        }

        return bytes_written;
    }
};
