const std = @import("std");
const tracy = @import("tracy");
const zttio = @import("zttio");

const ScreenVec = @import("../common/screen_vec.zig");
const Cell = @import("cell.zig");
const Screen = @import("screen.zig");
const ScreenStore = @import("screen_store.zig");

pub const View = @This();

screen: *Screen,

col: u16,
row: u16,
width: u16,
height: u16,

default_style: ScreenStore.StyleHandle,
overflow: Overflow,

pub inline fn strWidth(self: *const View, str: []const u8) usize {
    return self.screen.strWidth(str);
}

/// asserts that you are reading inside the view
pub inline fn readCell(self: *const View, row: u16, col: u16) Cell {
    std.debug.assert(row < self.height);
    std.debug.assert(col < self.width);

    return self.screen.readCell(self.col + col, self.row + row);
}

/// asserts that you are reading inside the view
pub fn getCellIndex(self: *const View, row: u16, col: u16) Cell.Index {
    std.debug.assert(row < self.height);
    std.debug.assert(col < self.width);

    return self.screen.getCellIndex(self.row + row, self.col + col);
}

/// asserts that you are writing inside the view if `.no_overflow`
/// 'store' only needs to be provided if a 'long_shared' content is given.
pub fn writeCellPos(self: *const View, store: ?*const ScreenStore, row: u16, col: u16, content: Cell.Content, opts: WriteCellOptions) u16 {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[ScreenView]: writeCell",
        .src = @src(),
    });
    defer trace_zone.end();

    if (self.overflow == .no_overflow) {
        std.debug.assert(col < self.width);
        std.debug.assert(row < self.height);
    } else if (row >= self.height or col >= self.width) {
        return 0;
    }

    const screen = self.screen;

    std.debug.assert(self.row + row < screen.winsize.rows);
    std.debug.assert(self.col + col < screen.winsize.cols);

    if (opts.max_width == 0) return 0;

    const width: u16 = content.calcWidth(screen, store);
    std.debug.assert(self.col + col + width <= screen.winsize.cols);
    if (opts.max_width) |max_width| {
        if (width > max_width) {
            self.fillPos(null, row, col, 1, max_width, .{ .char = ' ' }, .{
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
        self.fillPos(null, row, col + 1, 1, width - 1, .wide_continuation, .{
            .style = opts.style,
            .segment = opts.segment,
        });
    }

    return width;
}

/// asserts that you are writing inside the view if `.no_overflow`
/// 'store' only needs to be provided if a 'long_shared' content is given.
pub fn fillPos(self: *const View, store: ?*const ScreenStore, row: u16, col: u16, height: u16, width: u16, content: Cell.Content, opts: FillOptions) void {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[ScreenView]: fill",
        .src = @src(),
    });
    defer trace_zone.end();

    if (self.overflow == .no_overflow) {
        std.debug.assert(row < self.height);
        std.debug.assert(col + height - 1 < self.height);
        std.debug.assert(col < self.width);
        std.debug.assert(col + width - 1 < self.width);
    }

    const screen = self.screen;

    std.debug.assert(self.row + row < screen.winsize.rows);
    std.debug.assert(self.row + row + height - 1 < screen.winsize.rows);
    std.debug.assert(self.col + col < screen.winsize.cols);
    std.debug.assert(self.col + col + width - 1 < screen.winsize.cols);

    const safe_height = @min(self.height - row, height);
    const safe_width = @min(self.width - col, width);

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
                    w += self.writeCellPos(store, row + @as(u16, @intCast(h)), col + w, content, .{
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
pub fn writePos(self: *const View, row: u16, col: u16, content: []const u8, opts: WriteOptions) std.mem.Allocator.Error!ScreenVec {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[ScreenView]: write",
        .src = @src(),
    });
    defer trace_zone.end();

    if (self.overflow == .no_overflow) {
        std.debug.assert(row < self.height);
        std.debug.assert(col < self.width);
    } else if (row >= self.height or col >= self.width) {
        return .zero;
    }

    const screen = self.screen;

    std.debug.assert(self.row + row < screen.winsize.rows);
    std.debug.assert(self.col + col < screen.winsize.cols);

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

        cur_col += self.writeCellPos(null, row + cur_row, col + cur_col, cell_content, .{
            .style = opts.style,
            .segment = opts.segment,
        });
    }

    return ScreenVec{
        .y = cur_col,
        .x = cur_row,
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
        std.debug.assert(row < self.height);
        std.debug.assert(row + other_view.height <= self.height);
        std.debug.assert(col < self.width);
        std.debug.assert(col + other_view.width <= self.width);
    } else if (row >= self.height or col >= self.width) {
        return;
    }

    const screen = self.screen;

    const safe_height = @min(self.height - row, other_view.height);
    const safe_width = @min(self.width - col, other_view.width);

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

/// asserts that you are slicing inside the view if `.no_overflow`
pub fn view(self: *const View, opts: Options) View {
    var w = opts.width orelse self.width - opts.col;
    var h = opts.height orelse self.height - opts.row;
    if (self.overflow == .no_overflow) {
        std.debug.assert(opts.col + w <= self.width);
        std.debug.assert(opts.row + h <= self.height);
    } else {
        if (opts.col + w > self.width) {
            w = self.width - @min(self.width, opts.col);
        }

        if (opts.row + h > self.height) {
            h = self.height - @min(self.height, opts.row);
        }
    }

    return View{
        .screen = self.screen,

        .col = self.col + opts.col,
        .row = self.row + opts.row,
        .width = w,
        .height = h,

        .default_style = opts.default_style,
        .overflow = opts.overflow,
    };
}

/// asserts that you are setting the cursor inside the view if `.no_overflow`
pub inline fn setCursorPos(self: *const View, pos: ScreenVec) void {
    if (self.overflow == .no_overflow) {
        std.debug.print("{d} < {d}\n", .{ pos.x, self.height });
        std.debug.assert(pos.x < self.height);
        std.debug.print("{d} < {d}\n", .{ pos.y, self.width });
        std.debug.assert(pos.y < self.width);
    }

    self.screen.cursor_pos = .{
        .x = self.row + pos.x,
        .y = self.col + pos.y,
    };
}

pub inline fn setCursorShape(self: *const View, shape: Screen.CursorShape) void {
    self.screen.cursor_shape = shape;
}

pub inline fn setCursorVisibility(self: *const View, visible: bool) void {
    self.screen.cursor_visible = visible;
}

pub const Options = struct {
    col: u16,
    row: u16,
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
