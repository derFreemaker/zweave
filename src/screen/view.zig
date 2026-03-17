const std = @import("std");
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
overflow: Overflow,

pub inline fn strWidth(self: *const View, str: []const u8) usize {
    return self.screen.strWidth(str);
}

/// asserts that you are reading inside the view
pub inline fn readCell(self: *const View, row: u16, col: u16) Cell {
    std.debug.assert(row < self.size.y);
    std.debug.assert(col < self.size.x);

    return self.screen.readCell(self.pos.x + col, self.pos.y + row);
}

/// asserts that you are reading inside the view
pub fn getCellIndex(self: *const View, row: u16, col: u16) Cell.Index {
    std.debug.assert(row < self.size.y);
    std.debug.assert(col < self.size.x);

    return self.screen.getCellIndex(self.pos.y + row, self.pos.x + col);
}

/// asserts that you are writing inside the view if `.no_overflow`
/// 'store' only needs to be provided if a 'long_shared' content is given.
pub fn writeCell(self: *const View, store: ?*const ScreenStore, row: u16, col: u16, content: Cell.Content, opts: WriteCellOptions) u16 {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[ScreenView]: writeCell",
        .src = @src(),
    });
    defer trace_zone.end();

    if (self.overflow == .no_overflow) {
        std.debug.assert(col < self.size.x);
        std.debug.assert(row < self.size.y);
    } else if (row >= self.size.y or col >= self.size.x) {
        return 0;
    }

    const screen = self.screen;

    std.debug.assert(self.pos.y + row < screen.winsize.rows);
    std.debug.assert(self.pos.x + col < screen.winsize.cols);

    if (opts.max_width == 0) return 0;

    const width: u16 = content.calcWidth(screen, store);
    std.debug.assert(self.pos.x + col + width <= screen.winsize.cols);
    if (opts.max_width) |max_width| {
        if (width > max_width) {
            self.fill(null, row, col, 1, max_width, .{ .char = ' ' }, .{
                .style = opts.style,
                .segment = opts.segment,
            });

            return max_width;
        }
    }

    const cell_index = self.getCellIndex(row, col);
    screen.buf[cell_index.value()] = .{
        .content = content,
        .style = if (opts.style.isInvalid()) self.default_style else opts.style,
        .segment = opts.segment,
    };

    if (width > 1) {
        self.fill(null, row, col + 1, 1, width - 1, .wide_continuation, .{
            .style = opts.style,
            .segment = opts.segment,
        });
    }

    return width;
}

/// asserts that you are writing inside the view if `.no_overflow`
/// 'store' only needs to be provided if a 'long_shared' content is given.
pub fn fill(self: *const View, store: ?*const ScreenStore, row: u16, col: u16, height: u16, width: u16, content: Cell.Content, opts: FillOptions) void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[ScreenView]: fill",
        .src = @src(),
    });
    defer trace_zone.end();

    if (self.overflow == .no_overflow) {
        std.debug.assert(row < self.size.y);
        std.debug.assert(col + height - 1 < self.size.y);
        std.debug.assert(col < self.size.x);
        std.debug.assert(col + width - 1 < self.size.x);
    }

    const screen = self.screen;

    std.debug.assert(self.pos.y + row < screen.winsize.rows);
    std.debug.assert(self.pos.y + row + height - 1 < screen.winsize.rows);
    std.debug.assert(self.pos.x + col < screen.winsize.cols);
    std.debug.assert(self.pos.x + col + width - 1 < screen.winsize.cols);

    const safe_height = @min(self.size.y - row, height);
    const safe_width = @min(self.size.x - col, width);

    if (safe_height == 0 or safe_width == 0) {
        return;
    }

    switch (content) {
        .wide_continuation, .char => {
            for (0..safe_height) |h| {
                const start_idx = self.getCellIndex(@intCast(row + h), col);
                const end_idx = self.getCellIndex(@intCast(row + h), col + safe_width - 1);
                @memset(screen.buf[start_idx.value() .. end_idx.value() + 1], Cell{
                    .content = content,
                    .style = opts.style,
                    .segment = opts.segment,
                });
            }
        },
        else => {
            for (0..safe_height) |h| {
                var w: u16 = 0;
                while (w < safe_width) {
                    w += self.writeCell(store, row + @as(u16, @intCast(h)), col + w, content, .{
                        .max_width = safe_width - w,

                        .style = opts.style,
                        .segment = opts.segment,
                    });
                }
            }
        },
    }
}

/// asserts that you are writing inside the view if `.no_overflow`
pub fn write(self: *const View, row: u16, col: u16, content: []const u8, opts: WriteOptions) std.mem.Allocator.Error!ScreenVec {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[ScreenView]: write",
        .src = @src(),
    });
    defer trace_zone.end();

    if (self.overflow == .no_overflow) {
        std.debug.assert(row < self.size.y);
        std.debug.assert(col < self.size.x);
    } else if (row >= self.size.y or col >= self.size.x) {
        return .zero;
    }

    const screen = self.screen;

    std.debug.assert(self.pos.y + row < screen.winsize.rows);
    std.debug.assert(self.pos.x + col < screen.winsize.cols);

    if (opts.max_height != null and opts.max_height == 0) {
        return .zero;
    }
    if (opts.max_width != null and opts.max_width == 0) {
        return .zero;
    }

    const Unicode = @import("../common/unicode.zig");

    var cur_col: u16 = 0;
    var cur_row: u16 = 0;
    var grapheme_iter = Unicode.GraphemeClusterIterator.init(content);
    while (grapheme_iter.next()) |grapheme| {
        const str = grapheme.bytes(content);

        var cell_content: Cell.Content = undefined;
        if (str.len <= Cell.shortStringMaxLength) {
            switch (str.len) {
                0 => cell_content = .wide_continuation,
                1 => {
                    const c = str[0];
                    if (c == '\n') {
                        if (opts.max_height != null and cur_row + 1 >= opts.max_height.?) {
                            return ScreenVec{ .x = cur_row + 1, .y = cur_col };
                        }

                        cur_col = 0;
                        cur_row += 1;
                        continue;
                    } else if (c == '\r') {
                        if (grapheme.start + 1 < content.len and content[grapheme.start + 1] == '\n') {
                            grapheme_iter.skip();
                        }

                        if (opts.max_height != null and cur_row + 1 >= opts.max_height.?) {
                            return ScreenVec{ .x = cur_row + 1, .y = cur_col };
                        }

                        cur_col = 0;
                        cur_row += 1;
                        continue;
                    }

                    if (opts.max_width != null and cur_col >= opts.max_width.?) {
                        continue;
                    }

                    cell_content = .{ .char = c };
                },
                else => {
                    if (opts.max_width) |max_width| {
                        const str_width = self.strWidth(str);
                        if (cur_col + str_width > max_width) {
                            continue;
                        }
                    }

                    cell_content = .{ .short = [Cell.shortStringMaxLength]u8{ 0, 0, 0 } };
                    @memcpy(cell_content.short[0..str.len], str);

                    if (str.len < Cell.shortStringMaxLength) {
                        cell_content.short[str.len] = 0;
                    }
                },
            }
        } else {
            if (opts.max_width) |max_width| {
                const str_width = self.strWidth(str);
                if (cur_col + str_width > max_width) {
                    continue;
                }
            }

            const idx = try screen.addStr(str);
            cell_content = .{ .long_local = idx };
        }

        cur_col += self.writeCell(null, row + cur_row, col + cur_col, cell_content, .{
            .style = opts.style,
            .segment = opts.segment,
        });
    }

    return ScreenVec{
        .x = cur_col,
        .y = cur_row,
    };
}

/// asserts that the `other_view` fits inside the view if `.no_overflow`
pub fn projectView(self: *const View, other_view: *const View, row: u16, col: u16) std.mem.Allocator.Error!void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[ScreenView]: projectView",
        .src = @src(),
    });
    defer trace_zone.end();

    if (self.overflow == .no_overflow) {
        std.debug.assert(row < self.size.y);
        std.debug.assert(row + other_view.size.y <= self.size.y);
        std.debug.assert(col < self.size.x);
        std.debug.assert(col + other_view.size.x <= self.size.x);
    } else if (row >= self.size.y or col >= self.size.x) {
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
                self_buf[i].content.long_local = self_long_idx;
            }
        }
    }
}

pub fn writer(self: *const View, buffer: []u8) ViewWriter {
    return ViewWriter.init(self, buffer);
}

/// asserts that you are slicing inside the view if `.no_overflow`
pub fn view(self: *const View, opts: Options) View {
    var w = opts.width orelse self.size.x - opts.col;
    var h = opts.height orelse self.size.y - opts.row;
    if (self.overflow == .no_overflow) {
        std.debug.assert(opts.col + w <= self.size.x);
        std.debug.assert(opts.row + h <= self.size.y);
    } else {
        if (opts.col + w > self.size.x) {
            w = self.size.x - @min(self.size.x, opts.col);
        }

        if (opts.row + h > self.size.y) {
            h = self.size.y - @min(self.size.y, opts.row);
        }
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
        .overflow = opts.overflow,
    };
}

/// asserts that you are setting the cursor inside the view if `.no_overflow`
pub inline fn setCursorPos(self: *const View, pos: ScreenVec) void {
    if (self.overflow == .no_overflow) {
        std.debug.assert(pos.y < self.size.y);
        std.debug.assert(pos.x < self.size.x);
    }

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

pub const Options = struct {
    col: u16 = 0,
    row: u16 = 0,
    width: ?u16 = null,
    height: ?u16 = null,

    default_style: ScreenStore.StyleHandle = .invalid,
    overflow: Overflow = .allow_overflow,
};

pub const Overflow = enum(u1) {
    no_overflow,
    allow_overflow,
};

pub const FillOptions = struct {
    style: ScreenStore.StyleHandle = .invalid,
    segment: ScreenStore.SegmentHandle = .invalid,
};

pub const WriteCellOptions = struct {
    max_width: ?u16 = null,

    style: ScreenStore.StyleHandle = .invalid,
    segment: ScreenStore.SegmentHandle = .invalid,
};

pub const WriteOptions = struct {
    max_width: ?u16 = null,
    max_height: ?u16 = null,

    style: ScreenStore.StyleHandle = .invalid,
    segment: ScreenStore.SegmentHandle = .invalid,
};

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

            if (!line.last()) {
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
