const std = @import("std");
const zttio = @import("zttio");

const Unicode = @import("unicode.zig");
const Styling = @import("styling.zig");
const Cell = @import("cell.zig");
const Block = Cell.Block;

const Screen = @This();

allocator: std.mem.Allocator,
buf: []Cell,
capacity: u32,

str_pool: std.ArrayList(u8),
styles: std.ArrayList(Styling.Style),
segments: std.ArrayList(Block),

winsize: zttio.Winsize,
width_method: zttio.gwidth.Method = .wcwidth,
// cursor_row: u16 = 0,
// cursor_col: u16 = 0,
// cursor_visible: bool = false,
// mouse_shape: zttio.Mouse.Shape = .default,
// cursor_shape: zttio.ctlseqs.Cursor.Shape = .blinking_bar,

pub fn init(allocator: std.mem.Allocator, winsize: zttio.Winsize, width_method: zttio.gwidth.Method) std.mem.Allocator.Error!Screen {
    const buf = try allocator.alloc(Cell, winsize.cols * winsize.rows);
    errdefer allocator.free(buf);
    @memset(buf, Cell{});

    var str_pool = try std.ArrayList(u8).initCapacity(allocator, 2 * 1024);
    errdefer str_pool.deinit(allocator);

    var styles = try std.ArrayList(Styling.Style).initCapacity(allocator, 32);
    errdefer styles.deinit(allocator);

    var segments = try std.ArrayList(Block).initCapacity(allocator, 64);
    errdefer segments.deinit(allocator);

    return Screen{
        .allocator = allocator,
        .buf = buf,
        .capacity = @intCast(buf.len),

        .str_pool = str_pool,
        .styles = styles,
        .segments = segments,

        .winsize = winsize,
        .width_method = width_method,
    };
}

pub fn deinit(self: *Screen) void {
    self.allocator.free(self.buf.ptr[0..self.capacity]);
    self.str_pool.deinit(self.allocator);
    self.styles.deinit(self.allocator);
    self.segments.deinit(self.allocator);
}

/// this doesn't clear any data leaving it in an undefined buffer state
pub fn resize(self: *Screen, new_winsize: zttio.Winsize) std.mem.Allocator.Error!void {
    if (std.mem.eql(u8, std.mem.asBytes(&self.winsize), std.mem.asBytes(&new_winsize))) {
        return;
    }

    self.winsize = new_winsize;

    const new_capacity = new_winsize.cols * new_winsize.rows;
    if (new_capacity < self.capacity) {
        self.buf.len = new_capacity;
        return;
    }

    const old_memory = self.buf;
    if (self.allocator.remap(old_memory, new_capacity)) |new_memory| {
        self.buf = new_memory;
    } else {
        self.allocator.free(old_memory);
        self.buf = try self.allocator.alloc(Cell, new_capacity);
    }
    self.capacity = @intCast(self.buf.len);
}

pub fn clearGrid(self: *Screen) void {
    @memset(self.buf, Cell{});
}

pub fn clear(self: *Screen) void {
    self.clearGrid();
    self.str_pool.clearRetainingCapacity();
    self.styles.clearRetainingCapacity();
    self.segments.clearRetainingCapacity();
}

pub fn strWidth(self: *const Screen, str: []const u8) usize {
    return zttio.gwidth.gwidth(str, self.width_method);
}

pub fn registerStyle(self: *Screen, style: Styling.Style) std.mem.Allocator.Error!Styling.Index {
    // we could deduplicate here if necessary

    const index = Styling.Index.from(@intCast(self.styles.items.len));
    try self.styles.append(self.allocator, style);
    return index;
}

pub fn getStyle(self: *const Screen, index: Styling.Index) ?Styling.Style {
    if (self.styles.items.len <= index.value()) return null;
    return self.styles.items[index.value()];
}

pub fn registerBlock(self: *Screen, block: Block) std.mem.Allocator.Error!Block.Index {
    // we could deduplicate here if necessary

    const index = Block.Index.from(@intCast(self.segments.items.len));
    try self.segments.append(self.allocator, block);
    return index;
}

pub fn getBlock(self: *const Screen, index: Block.Index) ?Block {
    if (self.segments.items.len <= index.value()) return null;
    return self.segments.items[index.value()];
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
    } else if (content.len < 12) {
        cell_content = .{ .short = undefined };
        @memcpy(cell_content.short[0..content.len], content);
        if (content.len != 11) {
            cell_content.short[content.len] = 0;
        }
    } else {
        cell_content = .{ .long = .{
            .start = @intCast(self.str_pool.items.len),
            .end = @intCast(self.str_pool.items.len + content.len),
        } };
        try self.str_pool.appendSlice(self.allocator, content);
    }

    self.buf[row * self.winsize.cols + col] = .{
        .content = cell_content,
        .style = opts.style,
        .block = opts.block,
    };

    const wide_cell_index = self.getCellIndex(col, row);
    const wide_continuation_buf = self.buf[wide_cell_index.value() + 1 .. wide_cell_index.value() + width];
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
            .block = opts.block,
        });
    }

    return cur_col - col;
}

/// zero-based indexing
pub fn readCell(self: *const Screen, col: u16, row: u16) Cell {
    return self.buf[row * self.winsize.cols + col];
}

pub inline fn getCellIndex(self: *const Screen, col: u16, row: u16) Cell.Index {
    return Cell.Index.from(row * self.winsize.cols + col);
}

pub fn renderDirect(self: *const Screen, tty: *zttio.Tty) std.Io.Writer.Error!void {
    try tty.clearScreen(.entire);
    try tty.moveCursor(.home);

    var next_wrap: usize = self.winsize.cols;
    var current_style_index: Styling.Index = .invalid;
    var current_block_index: Block.Index = .invalid;
    var current_block: Block = undefined;
    for (self.buf, 0..) |cell, i| {
        if (i >= next_wrap) {
            try tty.stdout.writeByte('\n');
            next_wrap += self.winsize.cols;
        }
        if (cell.content == .wide_continuation) continue;

        if (cell.style != current_style_index) {
            if (cell.style == .invalid) {
                try tty.setStyling(.{});
            } else {
                const style = self.getStyle(cell.style).?;
                try tty.setStyling(style);
            }

            current_style_index = cell.style;
        }

        if (cell.block != current_block_index) {
            if (current_block_index != .invalid) {
                try current_block.end(tty.stdout);
            }

            if (cell.block != .invalid) {
                const block = self.getBlock(cell.block).?;
                try block.begin(tty.stdout);
                current_block = block;
            }

            current_block_index = cell.block;
        }

        switch (cell.content) {
            .char => |c| {
                try tty.stdout.writeByte(c);
            },
            .short => |s| {
                const end = std.mem.indexOf(u8, &s, &.{0}) orelse 11;
                try tty.stdout.writeAll(s[0..end]);
            },
            .long => |index| {
                try tty.stdout.writeAll(index.get(self.str_pool.items));
            },
            .wide_continuation => unreachable,
        }
    }
}

pub fn view(self: *Screen, col: u16, row: u16, width: ?u16, height: ?u16, overflow: Overflow) ScreenView {
    const w = width orelse self.winsize.cols - col;
    const h = height orelse self.winsize.rows - row;
    std.debug.assert(col + w <= self.winsize.cols);
    std.debug.assert(row + h <= self.winsize.rows);

    return ScreenView{
        .screen = self,
        .col = col,
        .row = row,
        .width = w,
        .height = h,
        .overflow = overflow,
    };
}

pub const ScreenView = struct {
    screen: *Screen,

    col: u16,
    row: u16,
    width: u16,
    height: u16,
    overflow: Overflow,

    pub inline fn strWidth(self: *const ScreenView, str: []const u8) usize {
        return self.screen.strWidth(str);
    }

    pub inline fn registerStyle(self: *ScreenView, style: Styling.Style) std.mem.Allocator.Error!Styling.Index {
        return self.screen.registerStyle(style);
    }

    pub inline fn getStyle(self: *const ScreenView, index: Styling.Index) ?Styling.Style {
        return self.screen.getStyle(index);
    }

    pub inline fn registerBlock(self: *ScreenView, block: Block) std.mem.Allocator.Error!Block.Index {
        return self.screen.registerBlock(block);
    }

    pub inline fn getBlock(self: *const ScreenView, index: Block.Index) ?Block {
        return self.screen.getBlock(index);
    }

    /// zero-based indexing
    ///
    /// asserts that you are writing inside the view if `.no_overflow`
    pub inline fn writeCell(self: *ScreenView, col: u16, row: u16, content: []const u8, opts: WriteOptions) std.mem.Allocator.Error!u16 {
        if (self.overflow == .no_overflow) {
            std.debug.assert(col < self.width);
            std.debug.assert(row < self.height);
        } else if (col >= self.width or row >= self.height) {
            return 0;
        }

        return self.screen.writeCell(self.col + col, self.row + row, content, opts);
    }

    /// zero-based indexing
    ///
    /// asserts that you are writing inside the view if `.no_overflow`
    pub inline fn write(self: *ScreenView, col: u16, row: u16, content: []const u8, opts: WriteOptions) std.mem.Allocator.Error!u16 {
        if (self.overflow == .no_overflow) {
            std.debug.assert(col < self.width);
            std.debug.assert(row < self.height);
        } else if (col >= self.width or row >= self.height) {
            return 0;
        }

        return self.screen.write(self.col + col, self.row + row, content, opts);
    }

    /// zero-based indexing
    ///
    /// asserts that you are reading inside the view
    pub inline fn readCell(self: *const ScreenView, col: u16, row: u16) Cell {
        std.debug.assert(col < self.width);
        std.debug.assert(row < self.height);

        return self.screen.readCell(self.col + col, self.row + row);
    }

    /// zero-based indexing
    ///
    /// asserts that you are reading inside the view
    pub inline fn getCellIndex(self: *const ScreenView, col: u16, row: u16) Cell.Index {
        std.debug.assert(col < self.width);
        std.debug.assert(row < self.height);

        return self.screen.getCellIndex(self.col + col, self.row + row);
    }

    /// asserts that you are slicing inside the view if `.no_overflow`
    pub fn view(self: *const ScreenView, col: u16, row: u16, width: ?u16, height: ?u16, overflow: Overflow) ScreenView {
        var w = width orelse self.width - col;
        var h = height orelse self.height - row;
        if (self.overflow == .no_overflow) {
            std.debug.assert(col + w <= self.width);
            std.debug.assert(row + h <= self.height);
        } else if (col + w >= self.width or row + h >= self.height) {
            w = self.width - @min(self.width, col);
            h = self.height - @min(self.height, row);
        }

        return ScreenView{
            .screen = self.screen,
            .col = self.col + col,
            .row = self.row + row,
            .width = w,
            .height = h,
            .overflow = overflow,
        };
    }
};

pub const Overflow = enum(u1) {
    no_overflow,
    allow_overflow,
};

pub const WriteOptions = struct {
    style: Styling.Index = .invalid,
    block: Block.Index = .invalid,
};
