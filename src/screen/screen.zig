const std = @import("std");
const zttio = @import("zttio");

const Cell = @import("../cell.zig");
const Segment = Cell.Segment;
const Style = @import("../styling.zig").Style;
const Unicode = @import("../unicode.zig");
const ScreenStore = @import("screen_store.zig");

const Screen = @This();

buf: []Cell,

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

    return Screen{
        .buf = buf,

        .winsize = winsize,
        .width_method = width_method,
    };
}

pub fn deinit(self: *Screen, allocator: std.mem.Allocator) void {
    allocator.free(self.buf);
}

/// this doesn't clear any data leaving the buffer in an undefined state
pub fn resize(self: *Screen, allocator: std.mem.Allocator, new_winsize: zttio.Winsize) std.mem.Allocator.Error!void {
    if (std.mem.eql(u8, std.mem.asBytes(&self.winsize), std.mem.asBytes(&new_winsize))) {
        return;
    }

    self.winsize = new_winsize;

    const new_capacity: usize = @as(usize, new_winsize.cols) * @as(usize, new_winsize.rows);
    if (new_capacity <= self.buf.len) {
        return;
    }

    if (allocator.resize(self.buf, new_capacity)) {
        self.buf.len = new_capacity;
    } else {
        allocator.free(self.buf);
        self.buf = try allocator.alloc(Cell, new_capacity);
    }
}

pub fn clear(self: *Screen) void {
    @memset(self.buf, Cell{});
}

pub fn strWidth(self: *const Screen, str: []const u8) usize {
    return zttio.gwidth.gwidth(str, self.width_method);
}

/// zero-based indexing
pub fn writeCell(self: *Screen, col: u16, row: u16, content: []const u8, opts: WriteOptions) std.mem.Allocator.Error!u16 {
    std.debug.assert(col < self.winsize.cols);
    std.debug.assert(row < self.winsize.rows);
    const width: u16 = @intCast(self.strWidth(content));
    std.debug.assert(col + width <= self.winsize.cols);

    var cell_content: Cell.Content = undefined;
    if (content.len == 0) {
        cell_content = .wide_continuation;
    } else if (content.len == 1) {
        cell_content = .{ .char = content[0] };
    } else if (content.len <= Cell.shortStringMaxLength) {
        cell_content = .{ .short = undefined };
        @memcpy(cell_content.short[0..content.len], content);
        if (content.len != Cell.shortStringMaxLength) {
            cell_content.short[content.len] = 0;
        }
    }
    // else {
    //     cell_content = .{ .long = .{
    //         .start = @intCast(self.str_pool.items.len),
    //         .end = @intCast(self.str_pool.items.len + content.len),
    //     } };
    //     try self.str_pool.appendSlice(self.allocator, content);
    // }

    self.buf[@as(usize, row) * @as(usize, self.winsize.cols) + @as(usize, col)] = .{
        .content = cell_content,
        .style = opts.style,
        .block = opts.segment,
    };

    const wide_cell_index = self.getCellIndex(col, row);
    const wide_continuation_buf = self.buf[@as(usize, wide_cell_index.value()) + 1 .. @as(usize, wide_cell_index.value()) + @as(usize, width)];
    @memset(wide_continuation_buf, Cell{ .content = .wide_continuation });

    return width;
}

/// zero-based indexing
pub fn write(self: *Screen, col: u16, row: u16, content: []const u8, opts: WriteOptions) std.mem.Allocator.Error!u16 {
    std.debug.assert(col < self.winsize.cols);
    std.debug.assert(row < self.winsize.rows);

    var cur_col: u16 = col;
    const cur_row: u16 = row;
    var grapheme_iter = Unicode.GraphemeIterator.init(content);
    while (grapheme_iter.next()) |grapheme| {
        cur_col += try self.writeCell(cur_col, cur_row, grapheme.bytes(content), .{
            .style = opts.style,
            .segment = opts.segment,
        });
    }

    return cur_col - col;
}

/// zero-based indexing
pub fn readCell(self: *const Screen, col: u16, row: u16) Cell {
    return self.buf[row * self.winsize.cols + col];
}

pub inline fn getCellIndex(self: *const Screen, col: u16, row: u16) Cell.Index {
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
        if (cell.content == .wide_continuation) continue;

        if (!cell.style.eql(current_style_handle)) {
            if (cell.style.isInvalid()) {
                try tty.setStyling(&Style{});
            } else {
                const style = store.getStyle(cell.style);
                try tty.setStyling(style);
            }

            current_style_handle = cell.style;
        }

        if (!cell.block.eql(current_segment_handle)) {
            if (!current_segment_handle.isInvalid()) {
                try current_segment.end(tty.stdout);
            }

            if (!cell.block.isInvalid()) {
                const segment = store.getSegment(cell.block);
                try segment.begin(tty.stdout);
                current_segment = segment;
            }

            current_segment_handle = cell.block;
        }

        switch (cell.content) {
            .char => |c| {
                try tty.stdout.writeByte(c);
            },
            .short => |s| {
                const end = std.mem.indexOf(u8, &s, &.{0}) orelse 11;
                try tty.stdout.writeAll(s[0..end]);
                i += end - 1;
            },
            // .long => |index| {
            //     const str = index.get(self.str_pool.items);
            //     try tty.stdout.writeAll(str);
            //     i += str.len - 1;
            // },
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

    /// zero-based indexing
    ///
    /// asserts that you are writing inside the view if `.no_overflow`
    pub inline fn writeCell(self: *const View, col: u16, row: u16, content: []const u8, opts: WriteOptions) std.mem.Allocator.Error!u16 {
        if (self.overflow == .no_overflow) {
            std.debug.assert(col < self.width);
            std.debug.assert(row < self.height);
        } else if (col >= self.width or row >= self.height) {
            return 0;
        }

        return self.screen.writeCell(self.col + col, self.row + row, content, blk: {
            if (opts.style.isInvalid()) {
                break :blk WriteOptions{
                    .style = self.default_style,
                    .segment = opts.segment,
                };
            }

            break :blk opts;
        });
    }

    /// zero-based indexing
    ///
    /// asserts that you are writing inside the view if `.no_overflow`
    pub inline fn write(self: *const View, col: u16, row: u16, content: []const u8, opts: WriteOptions) std.mem.Allocator.Error!u16 {
        if (self.overflow == .no_overflow) {
            std.debug.assert(col < self.width);
            std.debug.assert(row < self.height);
        } else if (col >= self.width or row >= self.height) {
            return 0;
        }

        return self.screen.write(self.col + col, self.row + row, content, blk: {
            if (opts.style.isInvalid()) {
                break :blk WriteOptions{
                    .style = self.default_style,
                    .segment = opts.segment,
                };
            }

            break :blk opts;
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

        return self.screen.getCellIndex(self.col + col, self.row + row);
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

pub const WriteOptions = struct {
    style: ScreenStore.StyleHandle = .invalid,
    segment: ScreenStore.SegmentHandle = .invalid,
};
