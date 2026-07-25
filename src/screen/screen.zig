const std = @import("std");

const tracy = @import("tracy");
const zttio = @import("zttio");
pub const CursorShape = zttio.ctlseqs.Cursor.Shape;

const IndexT = @import("../common/index.zig").IndexT;
const Unicode = @import("../unicode.zig");
const Cell = @import("cell.zig");
const ScreenStore = @import("screen_store.zig");
const ScreenVec = @import("screen_vec.zig");
const Segment = @import("segment.zig");
const Styling = @import("styling.zig").Styling;
const View = @import("view.zig");

const Screen = @This();

pub const StrIndex = IndexT([]const u8, u32);

allocator: std.mem.Allocator,

store: *ScreenStore,

buf: []Cell,

str_arena: std.heap.ArenaAllocator,
strs: std.ArrayList([]u8),

styles: std.ArrayList(ScreenStore.StylingHandle),

size: ScreenVec,
width_method: Unicode.WidthMethod = .wcwidth,

cursor_pos: ScreenVec,
cursor_visible: bool,
cursor_shape: CursorShape,

// mouse_shape: zttio.Mouse.Shape = .default,

pub fn init(allocator: std.mem.Allocator, store: *ScreenStore, size: ScreenVec, width_method: Unicode.WidthMethod) std.mem.Allocator.Error!Screen {
    const buf = try allocator.alloc(Cell, @as(u32, size.x) * @as(u32, size.y));
    errdefer allocator.free(buf);
    @memset(buf, Cell{});

    const str_arena = std.heap.ArenaAllocator.init(allocator);
    var strs = try std.ArrayList([]u8).initCapacity(allocator, 32);
    errdefer strs.deinit(allocator);

    var styles = try std.ArrayList(ScreenStore.StylingHandle).initCapacity(allocator, 64);
    errdefer styles.deinit(allocator);

    return Screen{
        .allocator = allocator,

        .store = store,

        .buf = buf,

        .str_arena = str_arena,
        .strs = strs,

        .styles = styles,

        .size = size,
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

    self.styles.deinit(self.allocator);
}

/// this doesn't clear any data leaving the buffer in an undefined state
pub fn resize(self: *Screen, new_size: ScreenVec) std.mem.Allocator.Error!void {
    if (self.size.x == new_size.x and self.size.y == new_size.y) {
        return;
    }

    self.size = new_size;

    const new_capacity: u32 = @as(u32, new_size.x) * @as(u32, new_size.y);
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

    // we only clear what we need to
    @memset(self.buf[0..self.len()], Cell{});

    self.strs.clearRetainingCapacity();
    _ = self.str_arena.reset(.{ .retain_with_limit = 1024 * 1024 });

    for (self.styles.items) |styling_handle| {
        self.store.removeStyling(styling_handle);
    }
    self.styles.clearRetainingCapacity();

    self.cursor_pos = .zero;
    self.cursor_shape = .blinking_bar;
    self.cursor_visible = false;
}

pub inline fn len(self: *const Screen) u32 {
    return @as(u32, self.size.x) * @as(u32, self.size.y);
}

pub inline fn strWidth(self: *const Screen, str: []const u8) usize {
    return Unicode.strWidth(str, self.width_method);
}

pub inline fn validCellIdx(self: *const Screen, cell_idx: Cell.Index) bool {
    return cell_idx.value() < self.len();
}

pub inline fn readCell(self: *const Screen, col: u16, row: u16) Cell {
    std.debug.assert(row < self.size.y);
    std.debug.assert(col < self.size.x);

    return self.buf[row * self.size.x + col];
}

/// the returned cell index is not guaranteed to be valid
pub inline fn getCellIndex(self: *const Screen, row: u16, col: u16) Cell.Index {
    std.debug.assert(row <= self.size.y);
    std.debug.assert(col <= self.size.x);

    const IntT = Cell.Index.UnderlyingT;
    const cell_idx = @as(IntT, row) * @as(IntT, self.size.x) + @as(IntT, col);
    return Cell.Index.from(cell_idx);
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

/// Get's cleanup after the next frame, if not the same styling was already stored.
pub fn addFrameStyling(self: *Screen, styling: Styling) std.mem.Allocator.Error!ScreenStore.StylingHandle {
    // @TODO: dedupe styling (unique custom hash? / HashMap?)

    const handle = try self.store.addStyling(styling);
    errdefer self.store.removeStyling(handle);

    try self.styles.append(self.allocator, handle);

    return handle;
}

/// asserts that you are slicing inside the screen
pub fn view(self: *Screen, opts: View.Options) View {
    std.debug.assert(opts.pos.x <= self.size.x);
    std.debug.assert(opts.pos.y <= self.size.y);

    const size = if (opts.size) |size| size.min(self.size.sub(opts.pos)) else self.size.sub(opts.pos);

    return View{
        .screen = self,

        .pos = opts.pos,
        .size = size,
    };
}

pub fn diff(self: *const Screen, other: *const Screen) ScreenDiffIterator {
    return ScreenDiffIterator.init(self, other);
}

pub const ScreenDiffIterator = struct {
    first: *const Screen,
    second: *const Screen,

    idx: Cell.Index,
    end: Cell.Index,

    current_styling: ScreenStore.StylingHandle = .invalid,

    pub fn init(first: *const Screen, second: *const Screen) ScreenDiffIterator {
        std.debug.assert(first.len() == second.len());

        return ScreenDiffIterator{
            .first = first,
            .second = second,

            .idx = .from(0),
            .end = .from(first.len()),
        };
    }

    pub fn next(self: *ScreenDiffIterator) ?CellDiff {
        while (self.idx.value() < self.end.value()) {
            defer self.idx.inc(1);

            const first = &self.first.buf[self.idx.value()];
            const second = &self.second.buf[self.idx.value()];
            if (first.eql(self.first, second, self.second) and
                self.current_styling.eql(second.styling)) // we have to check for any style change since the following cells might depend on them
            {
                continue;
            }
            self.current_styling = second.styling;

            return CellDiff{
                .idx = self.idx,
                .cell = second,
            };
        }

        return null;
    }

    pub const CellDiff = struct {
        idx: Cell.Index,
        cell: *const Cell,
    };
};
