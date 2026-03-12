const std = @import("std");
const zttio = @import("zttio");

const Cell = @import("cell.zig");
const Segment = @import("segment.zig");
const Style = @import("styling.zig").Style;
const ScreenStore = @import("screen_store.zig");
const IndexT = @import("../index.zig").IndexT;

const Screen = @This();

pub const StrIndex = IndexT([]const u8, u16);

allocator: std.mem.Allocator,

buf: []Cell,

str_arena: std.heap.ArenaAllocator,
strs: std.ArrayList([]u8),

winsize: zttio.Winsize,
width_method: zttio.gwidth.Method = .wcwidth,
// cursor_row: u16 = 0,
// cursor_col: u16 = 0,
// cursor_visible: bool = false,
// mouse_shape: zttio.Mouse.Shape = .default,
// cursor_shape: zttio.ctlseqs.Cursor.Shape = .blinking_bar,

pub fn init(allocator: std.mem.Allocator, winsize: zttio.Winsize, width_method: zttio.gwidth.Method) std.mem.Allocator.Error!Screen {
    const buf = try allocator.alloc(Cell, @as(usize, winsize.cols) * @as(usize, winsize.rows));
    errdefer allocator.free(buf);
    @memset(buf, Cell{});

    const str_arena = std.heap.ArenaAllocator.init(allocator);
    var strs = try std.ArrayList([]u8).initCapacity(allocator, 32);
    errdefer strs.deinit(allocator);

    return Screen{
        .allocator = allocator,

        .buf = buf,

        .str_arena = str_arena,
        .strs = strs,

        .winsize = winsize,
        .width_method = width_method,
    };
}

pub fn deinit(self: *Screen) void {
    self.allocator.free(self.buf);

    self.str_arena.deinit();
    self.strs.deinit(self.allocator);
}

/// this doesn't clear any data leaving the buffer in an undefined state
pub fn resize(self: *Screen, new_winsize: zttio.Winsize) std.mem.Allocator.Error!void {
    if (std.mem.eql(u8, std.mem.asBytes(&self.winsize), std.mem.asBytes(&new_winsize))) {
        return;
    }

    self.winsize = new_winsize;

    const new_capacity: usize = @as(usize, new_winsize.cols) * @as(usize, new_winsize.rows);
    if (new_capacity <= self.buf.len) {
        return;
    }

    if (self.allocator.resize(self.buf, new_capacity)) {
        self.buf.len = new_capacity;
    } else {
        self.allocator.free(self.buf);
        self.buf = try self.allocator.alloc(Cell, new_capacity);
    }
}

pub fn clear(self: *Screen) void {
    @memset(self.buf, Cell{});

    self.strs.clearRetainingCapacity();
    _ = self.str_arena.reset(.{ .retain_with_limit = 1024 * 1024 });
}

pub fn strWidth(self: *const Screen, str: []const u8) usize {
    return zttio.gwidth.gwidth(str, self.width_method);
}

/// 'store' only needs to be provided if a 'long_shared' content is given.
pub fn fill(self: *Screen, store: ?*const ScreenStore, row: u16, col: u16, height: u16, width: u16, content: Cell.Content, opts: FillOptions) void {
    if (height == 0 or width == 0) {
        return;
    }

    std.debug.assert(row < self.winsize.rows);
    std.debug.assert(row + height - 1 < self.winsize.rows);
    std.debug.assert(col < self.winsize.cols);
    std.debug.assert(col + width - 1 < self.winsize.cols);

    for (0..height) |h| {
        if (content == .wide_continuation) {
            for (0..width) |w| {
                _ = self.writeCell(store, row + @as(u16, @intCast(h)), col + @as(u16, @intCast(w)), content, .{
                    .style = opts.style,
                    .segment = opts.segment,
                });
            }

            break;
        }

        var w: u16 = 0;
        while (w < width) {
            w += self.writeCell(store, row + @as(u16, @intCast(h)), col + w, content, .{
                .max_width = width - w,

                .style = opts.style,
                .segment = opts.segment,
            });
        }
    }
}

/// zero-based indexing
/// 'store' only needs to be provided if a 'long_shared' content is given.
pub fn writeCell(self: *Screen, store: ?*const ScreenStore, row: u16, col: u16, content: Cell.Content, opts: WriteCellOptions) u16 {
    std.debug.assert(row < self.winsize.rows);
    std.debug.assert(col < self.winsize.cols);

    const width: u16 = content.calcWidth(self, store);
    std.debug.assert(col + width <= self.winsize.cols);
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
    self.buf[cell_index.value()] = .{
        .content = content,
        .style = opts.style,
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

/// zero-based indexing
pub fn write(self: *Screen, col: u16, row: u16, content: []const u8, opts: WriteOptions) std.mem.Allocator.Error!void {
    std.debug.assert(col < self.winsize.cols);
    std.debug.assert(row < self.winsize.rows);

    const Unicode = @import("unicode.zig");

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
                        if (opts.max_height) |max_height| {
                            if (cur_row > max_height) {
                                return;
                            }
                        }

                        cur_col = 0;
                        cur_row += 1;
                        continue;
                    }

                    if (opts.max_width) |max_width| {
                        if (cur_col >= max_width) {
                            continue;
                        }
                    }

                    cell_content = .{ .char = c };
                },
                else => {
                    const str_width = self.strWidth(str);

                    if (opts.max_width) |max_width| {
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

            const index = StrIndex.from(@intCast(self.strs.items.len));
            if (index.value() > self.strs.capacity) {
                try self.strs.ensureTotalCapacity(self.allocator, self.strs.capacity + 1);
            }

            const str_local: *[]u8 = self.strs.addOneAssumeCapacity();
            str_local.* = try self.str_arena.allocator().dupe(u8, str);

            cell_content = .{ .long_local = index };
        }

        cur_col += self.writeCell(null, row + cur_row, col + cur_col, cell_content, .{
            .style = opts.style,
            .segment = opts.segment,
        });
    }
}

/// zero-based indexing
pub fn readCell(self: *const Screen, col: u16, row: u16) Cell {
    return self.buf[row * self.winsize.cols + col];
}

pub inline fn getCellIndex(self: *const Screen, row: u16, col: u16) Cell.Index {
    return Cell.Index.from(@as(Cell.Index.UnderlyingT, row) * @as(Cell.Index.UnderlyingT, self.winsize.cols) + @as(Cell.Index.UnderlyingT, col));
}

pub fn renderDirect(self: *const Screen, store: *const ScreenStore, tty: *zttio.Tty) std.Io.Writer.Error!void {
    try tty.clearScreen(.entire);
    try tty.moveCursor(.home);

    const end_of_buffer = @as(usize, self.winsize.cols) * @as(usize, self.winsize.rows);

    var next_wrap: usize = self.winsize.cols;
    var current_style_handle: ScreenStore.StyleHandle = .invalid;
    var current_segment_handle: ScreenStore.SegmentHandle = .invalid;
    var current_segment: *const Segment = undefined;
    var i: usize = 0;
    while (i < end_of_buffer) : (i += 1) {
        const cell = self.buf[i];
        if (i >= next_wrap) {
            try tty.stdout.writeByte('\n');
            next_wrap += self.winsize.cols;
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
            .char => |c| {
                try tty.stdout.writeByte(c);
            },
            .short => |s| {
                const end = std.mem.indexOf(u8, &s, &.{0}) orelse 11;
                try tty.stdout.writeAll(s[0..end]);
            },
            .long_local => |index| {
                const str = self.strs.items[index.value()];
                try tty.stdout.writeAll(str);
            },
            .long_shared => |handle| {
                const str = store.getStr(handle);
                try tty.stdout.writeAll(str);
            },
            .wide_continuation => unreachable,
        }
    }
}

pub fn view(self: *Screen, opts: View.Options) View {
    std.debug.assert(opts.col <= self.winsize.cols);
    std.debug.assert(opts.row <= self.winsize.rows);

    const w = opts.width orelse self.winsize.cols - opts.col;
    const h = opts.height orelse self.winsize.rows - opts.row;

    std.debug.assert(opts.col + w <= self.winsize.cols);
    std.debug.assert(opts.row + h <= self.winsize.rows);

    return View{
        .screen = self,

        .col = opts.col,
        .row = opts.row,
        .width = w,
        .height = h,

        .default_style = opts.default_style,
        .overflow = opts.overflow,
    };
}

pub const View = struct {
    pub const Options = struct {
        col: u16,
        row: u16,
        width: ?u16 = null,
        height: ?u16 = null,

        default_style: ScreenStore.StyleHandle = .invalid,
        overflow: Overflow = .allow_overflow,
    };

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

    /// asserts that you are writing inside the view if `.no_overflow`
    /// 'store' only needs to be provided if a 'long_shared' content is given.
    pub fn fill(self: *View, store: ?*const ScreenStore, row: u16, col: u16, height: u16, width: u16, content: Cell.Content, opts: FillOptions) void {
        if (height == 0 or width == 0) {
            return;
        }

        if (self.overflow == .no_overflow) {
            std.debug.assert(row < self.height);
            std.debug.assert(col + height - 1 < self.height);
            std.debug.assert(col < self.width);
            std.debug.assert(col + width - 1 < self.width);

            for (0..height) |h| {
                var w: u16 = 0;
                while (w < width) {
                    w += self.writeCell(store, row + h, col + w, content, .{
                        .max_width = width - w,

                        .style = opts.style,
                        .segment = opts.segment,
                    });
                }
            }
        } else {
            const safe_height = @min(self.height, height);
            const safe_width = @min(self.width, width);

            for (0..safe_height) |h| {
                var w: u16 = 0;
                while (w < safe_width) {
                    w += self.writeCell(store, row + h, col + w, content, .{
                        .max_width = safe_width - w,

                        .style = opts.style,
                        .segment = opts.segment,
                    });
                }
            }
        }
    }

    /// zero-based indexing
    ///
    /// asserts that you are writing inside the view if `.no_overflow`
    /// 'store' only needs to be provided if a 'long_shared' content is given.
    pub inline fn writeCell(self: *const View, store: ?*const ScreenStore, row: u16, col: u16, content: Cell.Content, opts: WriteCellOptions) u16 {
        if (opts.max_width == 0) return 0;

        if (self.overflow == .no_overflow) {
            std.debug.assert(col < self.width);
            std.debug.assert(row < self.height);
        } else if (row >= self.height or col >= self.width) {
            return 0;
        }

        return self.screen.writeCell(store, self.row + row, self.col + col, content, .{
            .max_width = @min(opts.max_width orelse self.width, self.width),

            .style = if (opts.style.isInvalid()) self.default_style else opts.style,
            .segment = opts.segment,
        });
    }

    /// zero-based indexing
    ///
    /// asserts that you are writing inside the view if `.no_overflow`
    pub inline fn write(self: *const View, col: u16, row: u16, content: []const u8, opts: WriteOptions) std.mem.Allocator.Error!void {
        if (self.overflow == .no_overflow) {
            std.debug.assert(col < self.width);
            std.debug.assert(row < self.height);
        } else if (col >= self.width or row >= self.height) {
            return;
        }

        try self.screen.write(self.col + col, self.row + row, content, .{
            .max_width = if (col < self.width) self.width - col else 0,
            .max_height = if (row < self.height) self.height - row else 0,

            .style = if (opts.style.isInvalid()) self.default_style else opts.style,
            .segment = opts.segment,
        });
    }

    /// zero-based indexing
    ///
    /// asserts that you are reading inside the view
    pub inline fn readCell(self: *const View, col: u16, row: u16) Cell {
        std.debug.assert(col < self.width);
        std.debug.assert(row < self.height);

        return self.screen.readCell(self.col + col, self.row + row);
    }

    /// zero-based indexing
    ///
    /// asserts that you are reading inside the view
    pub inline fn getCellIndex(self: *const View, col: u16, row: u16) Cell.Index {
        std.debug.assert(col < self.width);
        std.debug.assert(row < self.height);

        return self.screen.getCellIndex(self.row + row, self.col + col);
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
