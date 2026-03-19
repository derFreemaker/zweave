const std = @import("std");
const tracy = @import("tracy");
const zttio = @import("zttio");

const ScreenVec = @import("../common/screen_vec.zig");
const IndexT = @import("../common/index.zig").IndexT;
const Cell = @import("cell.zig");
const Segment = @import("segment.zig");
const Style = @import("styling.zig").Style;
const ScreenStore = @import("screen_store.zig");
const View = @import("view.zig");

pub const CursorShape = zttio.ctlseqs.Cursor.Shape;

const Screen = @This();

pub const StrIndex = IndexT([]const u8, u16);

allocator: std.mem.Allocator,

buf: []Cell,

str_arena: std.heap.ArenaAllocator,
strs: std.ArrayList([]u8),

winsize: zttio.Winsize,
width_method: zttio.gwidth.Method = .wcwidth,

cursor_pos: ScreenVec,
cursor_visible: bool,
cursor_shape: CursorShape,

// mouse_shape: zttio.Mouse.Shape = .default,

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

        .cursor_pos = .zero,
        .cursor_visible = false,
        .cursor_shape = .blinking_bar,
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
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Screen]: clear",
        .src = @src(),
    });
    defer trace_zone.end();

    @memset(self.buf, Cell{});

    self.strs.clearRetainingCapacity();
    _ = self.str_arena.reset(.{ .retain_with_limit = 1024 * 1024 });

    self.cursor_pos = .zero;
    self.cursor_shape = .blinking_bar;
    self.cursor_visible = false;
}

pub inline fn len(self: *const Screen) u32 {
    return @as(u32, self.winsize.cols) * @as(u32, self.winsize.rows);
}

pub inline fn strWidth(self: *const Screen, str: []const u8) usize {
    const Unicode = @import("../common/unicode.zig");

    return Unicode.strWidth(str, self.width_method);
}

pub fn readCell(self: *const Screen, col: u16, row: u16) Cell {
    return self.buf[row * self.winsize.cols + col];
}

pub inline fn getCellIndex(self: *const Screen, row: u16, col: u16) Cell.Index {
    std.debug.assert(row < self.winsize.rows);
    std.debug.assert(col < self.winsize.cols);

    return Cell.Index.from(@as(Cell.Index.UnderlyingT, row) * @as(Cell.Index.UnderlyingT, self.winsize.cols) + @as(Cell.Index.UnderlyingT, col));
}

pub fn addStr(self: *Screen, str: []const u8) std.mem.Allocator.Error!StrIndex {
    const idx = StrIndex.from(@intCast(self.strs.items.len));

    const str_local: *[]u8 = try self.strs.addOne(self.allocator);
    str_local.* = try self.str_arena.allocator().dupe(u8, str);

    return idx;
}

pub inline fn getStr(self: *const Screen, idx: StrIndex) []const u8 {
    std.debug.assert(idx != .invalid);
    std.debug.assert(idx.value() < self.strs.items.len);

    return self.strs.items[idx.value()];
}

/// asserts that you are slicing inside the screen
pub fn view(self: *Screen, opts: View.Options) View {
    std.debug.assert(opts.col <= self.winsize.cols);
    std.debug.assert(opts.row <= self.winsize.rows);

    const w = opts.width orelse self.winsize.cols - opts.col;
    const h = opts.height orelse self.winsize.rows - opts.row;

    std.debug.assert(opts.col + w <= self.winsize.cols);
    std.debug.assert(opts.row + h <= self.winsize.rows);

    return View{
        .screen = self,

        .pos = .{ .x = opts.col, .y = opts.row },
        .size = .{ .x = w, .y = h },

        .default_style = opts.default_style,
        .overflow = opts.overflow,
    };
}

pub fn diff(self: *const Screen, other: *const Screen, out: *Screen) std.mem.Allocator.Error!void {
    std.debug.assert(self.len() == other.len());
    std.debug.assert(self.len() == out.len());
    std.debug.assert(self.width_method == other.width_method);

    const iter = ScreenDiffIterator.init(self, other);
    while (iter.next()) |cell_diff| {
        const cell = &out.buf[cell_diff.idx.value()];
        cell.* = cell_diff.cell.*;

        switch (cell_diff.cell.content) {
            .long_local => |long_idx| {
                cell.content.long_local = try out.addStr(other.getStr(long_idx));
            },
            else => {},
        }
    }

    out.width_method = other.width_method;

    out.cursor_pos = other.cursor_pos;
    out.cursor_shape = other.cursor_shape;
    out.cursor_visible = other.cursor_visible;
}

pub const ScreenDiffIterator = struct {
    first: *const Screen,
    second: *const Screen,

    idx: Cell.Index,
    end: Cell.Index,

    pub fn init(first: *const Screen, second: *const Screen) ScreenDiffIterator {
        std.debug.assert(first.len() == second.len());

        return ScreenDiffIterator{
            .first = first,
            .second = second,

            .idx = 0,
            .end = .from(first.len()),
        };
    }

    pub fn next(self: *ScreenDiffIterator) ?CellDiff {
        while (self.idx < self.end) {
            defer self.idx = self.idx.increment(1);

            const first = &self.first.buf[self.idx];
            const second = &self.second.buf[self.idx];

            if (!first.style.eql(second.style) or
                !first.segment.eql(second.segment) or
                std.meta.activeTag(first) != std.meta.activeTag(second))
            {
                return CellDiff{
                    .idx = self.idx,
                    .cell = second,
                };
            }

            switch (first.content) {
                .empty => {},
                .char => {
                    if (first.content.char != second.content.char) {
                        return CellDiff{
                            .idx = self.idx,
                            .cell = second,
                        };
                    }
                },
                .short => {
                    const first_content = first.content.short[0 .. std.mem.indexOf(u8, &first.content.short, &.{0}) orelse 8];
                    const second_content = second.content.short[0 .. std.mem.indexOf(u8, &second.content.short, &.{0}) orelse 8];
                    return std.mem.eql(first_content, second_content);
                },
                .long_local => {
                    return CellDiff{
                        .idx = self.idx,
                        .cell = second,
                    };
                },
                .long_shared => {
                    if (!first.content.long_shared.eql(second.content.long_shared)) {
                        return CellDiff{
                            .idx = self.idx,
                            .cell = second,
                        };
                    }
                },
                .wide_continuation => {},
            }
        }

        return null;
    }

    pub const CellDiff = struct {
        idx: Cell.Index,
        cell: *const Cell,
    };
};
