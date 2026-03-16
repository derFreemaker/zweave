const std = @import("std");
const tracy = @import("tracy");
const zttio = @import("zttio");

const ScreenVec = @import("../common/screen_vec.zig");
const Cell = @import("cell.zig");
const Segment = @import("segment.zig");
const Style = @import("styling.zig").Style;
const ScreenStore = @import("screen_store.zig");
const View = @import("view.zig");
const IndexT = @import("../index.zig").IndexT;

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

pub inline fn len(self: *const Screen) usize {
    return @as(usize, self.winsize.cols) * @as(usize, self.winsize.rows);
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

        .col = opts.col,
        .row = opts.row,
        .width = w,
        .height = h,

        .default_style = opts.default_style,
        .overflow = opts.overflow,
    };
}
