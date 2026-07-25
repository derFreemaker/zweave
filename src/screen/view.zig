const std = @import("std");
const builtin = @import("builtin");

const tracy = @import("tracy");
const zttio = @import("zttio");

const LineIterator = @import("../common/line_iterator.zig");
const Cell = @import("cell.zig");
const Screen = @import("screen.zig");
const ScreenStore = @import("screen_store.zig");
const ScreenVec = @import("screen_vec.zig");
const Styling = @import("styling.zig").Styling;

pub const View = @This();

screen: *Screen,

pos: ScreenVec,
size: ScreenVec,
mask_offset: ScreenVec = ScreenVec.zero,

pub inline fn strWidth(self: *const View, str: []const u8) usize {
    return self.screen.strWidth(str);
}

pub inline fn validCellIdx(self: *const View, cell_idx: Cell.Index) bool {
    return self.screen.validCellIdx(cell_idx);
}

/// asserts that you are reading inside the view
pub inline fn readCell(self: *const View, row: u16, col: u16) Cell {
    std.debug.assert(row < self.size.y);
    std.debug.assert(col < self.size.x);

    return self.screen.readCell(self.pos.x + col, self.pos.y + row);
}

/// the returned cell index is not guaranteed to be valid
pub inline fn getCellIndex(self: *const View, row: u16, col: u16) Cell.Index {
    std.debug.assert(row <= self.size.y);
    std.debug.assert(col <= self.size.x);

    return self.screen.getCellIndex(self.pos.y + row, self.pos.x + col);
}

/// returns `null` when position is not in the viewable area
pub fn calculatePosInViewableArea(self: *const View, pos: ScreenVec) ?ScreenVec {
    if (pos.x < self.mask_offset.x or
        pos.y < self.mask_offset.y or
        pos.x - self.mask_offset.x > self.size.x or
        pos.y - self.mask_offset.y > self.size.y)
    {
        return null;
    }
    return pos.sub(self.mask_offset);
}

/// `cell_idx` is the cell which is going to be overriden.
fn correctCellsFront(self: *const View, comptime inlined_loops: comptime_int, cell_idx: Cell.Index) void {
    if (cell_idx.value() <= 0 or
        self.screen.buf[cell_idx.value()].content != .skipped)
    {
        return;
    }

    // we start at 1 since '0' would be the cell which gets overriden anyway.
    inline for (1..inlined_loops + 1) |i| {
        const idx = 1 + cell_idx.value() - i;
        if (idx <= 0) {
            return;
        }

        const cell: *Cell = &self.screen.buf[idx - 1];
        if (cell.content != .skipped) {
            cell.content = .empty;
            return;
        }

        cell.content = .empty;
    }

    var i: usize = 1 + cell_idx.value() - inlined_loops;
    while (i > 0) : (i -= 1) {
        const cell: *Cell = &self.screen.buf[i - 1];
        if (cell.content != .skipped) {
            cell.content = .empty;
            return;
        }

        cell.content = .empty;
    }
}

/// `cell_idx` is the cell behind the overriden cell.
fn correctCellsEnd(self: *const View, comptime inlined_loops: comptime_int, cell_idx: Cell.Index) void {
    const buf_len = self.screen.len();

    inline for (0..inlined_loops) |i| {
        if (cell_idx.value() + i >= buf_len) {
            return;
        }

        const cell: *Cell = &self.screen.buf[cell_idx.value() + i];
        if (cell.content != .skipped) {
            return;
        }

        cell.content = .empty;
    }

    for (inlined_loops..buf_len) |i| {
        const cell: *Cell = &self.screen.buf[cell_idx.value() + i];
        if (cell.content != .skipped) {
            return;
        }

        cell.content = .empty;
    }
}

/// corrects the surounding cells of the given range
/// @Optimize
inline fn correctCells(self: *const View, start_idx: Cell.Index, end_idx: Cell.Index) void {
    const inlined_loops = 2;
    correctCellsFront(self, inlined_loops, start_idx);
    correctCellsEnd(self, inlined_loops, end_idx);
}

pub const WriteCellOptions = struct {
    max_width: ?u16 = null,

    styling: ScreenStore.StylingHandle = .invalid,
    segment: ScreenStore.SegmentHandle = .invalid,
};

pub fn writeCell(self: *const View, row: u16, col: u16, content: Cell.Content, opts: WriteCellOptions) u16 {
    const screen = self.screen;
    const width: u16 = content.calcWidth(screen);

    if (row < self.mask_offset.y) {
        return width;
    }

    const fill_cell = Cell{
        .content = .empty,
        .styling = opts.styling,
        .segment = opts.segment,
    };

    if (col < self.mask_offset.x) {
        if (col + width <= self.mask_offset.x) {
            return width;
        } else {
            const remaining_width = col + width - self.mask_offset.x;
            const draw_width = if (opts.max_width) |max_width| @min(remaining_width, max_width) else remaining_width;

            const cell_idx = self.getCellIndex(row - self.mask_offset.y, self.mask_offset.x);
            @memset(screen.buf[cell_idx.value() .. cell_idx.value() + draw_width], fill_cell);

            return width;
        }
    }

    const write_row = row - self.mask_offset.y;
    const write_col = col - self.mask_offset.x;
    if (write_row >= self.size.y or
        write_col >= self.size.x)
    {
        return width;
    }

    const cell_idx = self.getCellIndex(write_row, write_col);
    const end_cell_idx = cell_idx.add(width);
    if (opts.max_width) |max_width| {
        if (width > max_width) {
            @memset(screen.buf[cell_idx.value() .. cell_idx.value() + max_width], fill_cell);

            return max_width;
        }
    }
    if (self.pos.x + col + width > screen.size.x) {
        const remaining_width = screen.size.x - self.pos.x + col;
        @memset(screen.buf[cell_idx.value() .. cell_idx.value() + remaining_width], fill_cell);

        return remaining_width;
    }

    correctCells(self, cell_idx, end_cell_idx);

    screen.buf[cell_idx.value()] = .{
        .content = content,

        .styling = opts.styling,
        .segment = opts.segment,
    };
    @memset(screen.buf[cell_idx.value() + 1 .. end_cell_idx.value()], Cell{
        .content = .skipped,

        .styling = opts.styling,
        .segment = opts.segment,
    });

    return width;
}

pub const FillOptions = struct {
    styling: ScreenStore.StylingHandle = .invalid,
    segment: ScreenStore.SegmentHandle = .invalid,
};

pub fn fill(self: *const View, row: u16, col: u16, height: u16, width: u16, content: Cell.Content, opts: FillOptions) void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[ScreenView]: fill",
        .src = @src(),
    });
    defer trace_zone.end();

    if (height == 0 or
        width == 0 or
        row + height <= self.mask_offset.y or
        col + width <= self.mask_offset.x)
    {
        return;
    }

    const fill_row = row -| self.mask_offset.x;
    const fill_col = col -| self.mask_offset.y;

    const fill_height = height - (self.mask_offset.y -| row);
    const fill_width = width - (self.mask_offset.x -| col);

    if (fill_row >= self.size.y or fill_col >= self.size.x) {
        return;
    }

    const safe_height: u16 = @min(self.size.y - fill_row, fill_height);
    const safe_width: u16 = @min(self.size.x - fill_col, fill_width);

    const screen = self.screen;
    std.debug.assert(self.pos.y + fill_row < screen.size.y);
    std.debug.assert(self.pos.y + fill_row + safe_height - 1 < screen.size.y);
    std.debug.assert(self.pos.x + fill_col < screen.size.x);
    std.debug.assert(self.pos.x + fill_col + safe_width - 1 < screen.size.x);

    const cells = @max(content.calcWidth(screen), 1);
    if (cells == 1) {
        for (0..safe_height) |h| {
            const start_idx = self.getCellIndex(@intCast(fill_row + h), fill_col);
            const end_idx = start_idx.add(safe_width);
            @memset(screen.buf[start_idx.value()..end_idx.value()], Cell{
                .content = content,

                .styling = opts.styling,
                .segment = opts.segment,
            });
        }

        return;
    }

    const amount = std.math.divFloor(u16, safe_width, cells) catch unreachable;
    const remainder = std.math.rem(u16, safe_width, cells) catch unreachable;

    const content_cell = Cell{
        .content = content,

        .styling = opts.styling,
        .segment = opts.segment,
    };
    const skipped_cell = Cell{
        .content = .skipped,

        .styling = opts.styling,
        .segment = opts.segment,
    };

    for (0..safe_height) |h| {
        const row_idx = self.getCellIndex(@intCast(fill_row + h), fill_col);

        correctCells(self, row_idx, row_idx.add(safe_width));

        var current_col_idx = row_idx;
        for (0..amount) |_| {
            const end_idx = current_col_idx.add(cells);
            screen.buf[current_col_idx.value()] = content_cell;
            @memset(screen.buf[current_col_idx.value() + 1 .. end_idx.value()], skipped_cell);
            current_col_idx = end_idx;
        }

        const end_idx = current_col_idx.add(remainder);
        @memset(screen.buf[current_col_idx.value()..end_idx.value()], Cell{
            .content = .empty,

            .styling = opts.styling,
            .segment = opts.segment,
        });
    }
}

pub const WriteOptions = struct {
    max_width: ?u16 = null,
    max_height: ?u16 = null,

    styling: ScreenStore.StylingHandle = .invalid,
    segment: ScreenStore.SegmentHandle = .invalid,
};

/// Only allocates if a grapheme cluster is bigger than `Cell.CONTENT_SHORT_STR_MAX_LENGTH`.
// @Todo: optimize for mask_offset
// @Cleanup
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

    const Unicode = @import("../unicode.zig");

    var cur_col: u16 = 0;
    var cur_row: u16 = 0;
    var grapheme_cluster_iter = Unicode.GraphemeClusterIterator.init(content);
    while (grapheme_cluster_iter.next()) |grapheme_cluster| {
        const str = grapheme_cluster.bytes(&grapheme_cluster_iter);

        var cell_content: Cell.Content = undefined;
        switch (str.len) {
            0 => cell_content = .skipped,
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
                        if (opts.max_height) |max_height| {
                            if (cur_row + 1 >= max_height) {
                                return ScreenVec{ .x = cur_row + 1, .y = cur_col };
                            }
                        }

                        cur_col = 0;
                        cur_row += 1;
                        continue;
                    },
                    else => {},
                }

                if (opts.max_width) |max_width| {
                    if (cur_col >= max_width) {
                        continue;
                    }
                }

                cell_content = .{ .char = c };
            },

            2...Cell.CONTENT_SHORT_STR_MAX_LENGTH => {
                const str_width = self.strWidth(str);
                if (opts.max_width) |max_width| {
                    if (cur_col + str_width > max_width) {
                        continue;
                    }
                }

                cell_content = .{ .short = undefined };
                @memcpy(cell_content.short[0..str.len], str);
                if (str.len < Cell.CONTENT_SHORT_STR_MAX_LENGTH) {
                    cell_content.short[str.len] = 0;
                }
            },

            else => {
                const str_width = self.strWidth(str);
                if (opts.max_width) |max_width| {
                    if (cur_col + str_width > max_width) {
                        continue;
                    }
                }

                const idx = try screen.addStr(str);
                cell_content = .{ .frame_long = idx };
            },
        }

        cur_col += self.writeCell(row + cur_row, col + cur_col, cell_content, .{
            .max_width = if (opts.max_width) |max_width| max_width - cur_col else null,

            .styling = opts.styling,
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

    std.debug.assert(self.screen.store == other_view.screen.store);

    if (row + other_view.size.y <= self.mask_offset.y or
        col + other_view.size.x <= self.mask_offset.x)
    {
        return;
    }

    const project_row = row -| self.mask_offset.y;
    const project_col = col -| self.mask_offset.x;
    if (project_row >= self.size.y or
        project_col >= self.size.x)
    {
        return;
    }

    const offset_view = other_view.view(.{
        .pos = self.mask_offset.sub(.{ .x = col, .y = row }),
    });

    const screen = self.screen;
    const other_screen = offset_view.screen;

    const safe_height = @min(self.size.y - project_row, offset_view.size.y);
    const safe_width = @min(self.size.x - project_col, offset_view.size.x);

    for (0..safe_height) |h| {
        const self_start_idx = self.getCellIndex(project_row + @as(u16, @intCast(h)), project_col);
        const self_end_idx = self.getCellIndex(project_row + @as(u16, @intCast(h)), project_col + safe_width);
        const self_buf = self.screen.buf[self_start_idx.value()..self_end_idx.value()];

        correctCells(self, self_start_idx, self_end_idx);

        const other_start_idx = offset_view.getCellIndex(@intCast(h), 0);
        const other_end_idx = offset_view.getCellIndex(@intCast(h), safe_width);
        const other_buf = other_screen.buf[other_start_idx.value()..other_end_idx.value()];

        std.debug.assert(self_buf.len == other_buf.len);
        const buf_len = self_buf.len;

        var seen_complete_cell = false;
        for (0..buf_len) |i| {
            var cell: Cell = other_buf[i];

            switch (cell.content) {
                .skipped => {
                    if (!seen_complete_cell) {
                        cell.content = .empty;
                    }
                },
                .frame_long => {
                    seen_complete_cell = true;

                    const other_long_idx = other_buf[i].content.frame_long;

                    const self_long_idx = try screen.addStr(other_screen.getStr(other_long_idx));
                    cell.content = .{ .frame_long = self_long_idx };
                },
                else => {
                    seen_complete_cell = true;
                },
            }
            self_buf[i] = cell;
        }

        if (self_buf[buf_len - 1].content == .skipped) {
            var i = buf_len - 1;
            while (i >= 0) : (i -= 1) {
                const cell: *Cell = &self_buf[i];
                if (cell.content != .skipped) {
                    const width = cell.content.calcWidth(screen);
                    if (i + width > buf_len) {
                        for (i..buf_len) |j| {
                            self_buf[j].content = .empty;
                        }
                    }
                    break;
                }

                if (i == 0) {
                    for (0..buf_len) |j| {
                        self_buf[j].content = .empty;
                    }
                    break;
                }
            }
        }
    }
}

pub const Options = struct {
    pos: ScreenVec = ScreenVec.zero,
    size: ?ScreenVec = null,
    mask_offset: ScreenVec = ScreenVec.zero,
};

pub fn view(self: *const View, opts: Options) View {
    const view_size = self.size.sub(self.mask_offset).sub(opts.pos);

    return View{
        .screen = self.screen,

        .pos = self.pos.add(self.mask_offset).add(opts.pos),
        .size = if (opts.size) |size| size.min(view_size) else view_size,
        .mask_offset = opts.mask_offset,
    };
}

/// returns `true` if the position provieded is in the viewable area
pub inline fn setCursorPos(self: *const View, pos: ScreenVec) bool {
    if (pos.x < self.mask_offset.x or
        pos.y < self.mask_offset.y or
        pos.x - self.mask_offset.x > self.size.x or
        pos.y - self.mask_offset.y >= self.size.y)
    {
        return false;
    }

    self.screen.cursor_pos = .{
        .x = self.pos.x + (pos.x - self.mask_offset.x),
        .y = self.pos.y + (pos.y - self.mask_offset.y),
    };
    return true;
}

pub inline fn setCursorShape(self: *const View, shape: Screen.CursorShape) void {
    self.screen.cursor_shape = shape;
}

pub inline fn setCursorVisibility(self: *const View, visible: bool) void {
    self.screen.cursor_visible = visible;
}

pub fn writer(self: *const View, buffer: []u8, opts: ViewWriterOptions) ViewWriter {
    return ViewWriter.init(self, buffer, opts);
}

pub const ViewWriter = struct {
    view: View,
    interface: std.Io.Writer,

    styling: ScreenStore.StylingHandle,

    pos: ScreenVec = .zero,

    pub fn init(view_ptr: *const View, buffer: []u8, opts: ViewWriterOptions) ViewWriter {
        return ViewWriter{
            .view = view_ptr.*,
            .interface = std.Io.Writer{
                .buffer = buffer,
                .vtable = &std.Io.Writer.VTable{
                    .drain = drain,
                },
            },

            .styling = opts.styling,
        };
    }

    // @Optimize
    fn write(self: *ViewWriter, content: []const u8) std.Io.Writer.Error!void {
        var line_iter = LineIterator.init(content);
        while (line_iter.peek()) |line| : (line_iter.toss(line)) {
            const end_pos = self.view.write(self.pos.y, self.pos.x, line.content(&line_iter), .{
                .styling = self.styling,
            }) catch return error.WriteFailed;
            self.pos.x += end_pos.x;

            if (line.hasSeparator()) {
                self.pos.x = 0;
                self.pos.y += 1;
            }
        }
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *ViewWriter = @fieldParentPtr("interface", w);

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

pub const ViewWriterOptions = struct {
    styling: ScreenStore.StylingHandle = .invalid,
};
