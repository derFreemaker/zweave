const std = @import("std");
const math = @import("math.zig");

const GapBuffer = @import("gap_buffer.zig").GapBuffer;

const GraphemeGapBuffer = @This();

buf: GapBuffer(u8),
graphemes_len: GapBuffer(u16),
// max_display_width: u16,

pub const empty = GraphemeGapBuffer{
    .buf = .empty,
    .graphemes_len = .empty,
};

pub fn initCapacity(allocator: std.mem.Allocator, n: usize) std.mem.Allocator.Error!GraphemeGapBuffer {
    var buf = try GapBuffer(u8).initCapacity(allocator, n);
    errdefer buf.deinit(allocator);

    var graphemes = try GapBuffer(u16).initCapacity(allocator, n);
    errdefer graphemes.deinit(allocator);

    return GraphemeGapBuffer{
        .buf = buf,
        .graphemes_len = graphemes,
    };
}

pub fn deinit(self: *GraphemeGapBuffer, allocator: std.mem.Allocator) void {
    self.buf.deinit(allocator);
    self.graphemes_len.deinit(allocator);
}

pub fn clearAndFree(self: *GraphemeGapBuffer, allocator: std.mem.Allocator) void {
    self.buf.clearAndFree(allocator);
    self.graphemes_len.clearAndFree(allocator);
}

pub fn clearRetainingCapacity(self: *GraphemeGapBuffer) void {
    self.buf.clearRetainingCapacity();
    self.graphemes_len.clearRetainingCapacity();
}

pub inline fn len(self: *const GraphemeGapBuffer) usize {
    return self.buf.len();
}

pub inline fn graphemeCount(self: *const GraphemeGapBuffer) usize {
    return self.graphemes_len.len();
}

pub inline fn firstHalf(self: *const GraphemeGapBuffer) []const u8 {
    return self.buf.firstHalf();
}

pub inline fn secondHalf(self: *const GraphemeGapBuffer) []const u8 {
    return self.buf.secondHalf();
}

pub fn insertGrapheme(self: *GraphemeGapBuffer, allocator: std.mem.Allocator, grapheme: []const u8) std.mem.Allocator.Error!void {
    try self.graphemes_len.insert(allocator, @intCast(grapheme.len));
    errdefer _ = self.graphemes_len.growGapLeft(1);

    try self.buf.insertSlice(allocator, grapheme);
    errdefer _ = self.buf.growGapLeft(grapheme.len);
}

pub fn insertGraphemeSlice(self: *GraphemeGapBuffer, allocator: std.mem.Allocator, slice: []const u8) std.mem.Allocator.Error!void {
    const Unicode = @import("unicode.zig");

    var grapheme_iter = Unicode.GraphemeClusterIterator.init(slice);
    while (grapheme_iter.next()) |grapheme| {
        try self.insertGrapheme(allocator, grapheme.bytes(slice));
    }
}

pub fn moveGapLeft(self: *GraphemeGapBuffer, n: usize) ?[]u8 {
    const graphemes_len = self.graphemes_len.moveGapLeft(n) orelse return null;
    const bytes_len = math.sum(u16, graphemes_len);

    return self.buf.moveGapLeft(bytes_len) orelse @panic("grapheme buffer desync");
}

pub fn moveGapRight(self: *GraphemeGapBuffer, n: usize) ?[]u8 {
    const graphemes_len = self.graphemes_len.moveGapRight(n) orelse return null;
    const bytes_len = math.sum(u16, graphemes_len);

    return self.buf.moveGapRight(bytes_len) orelse @panic("grapheme buffer desync");
}

pub inline fn canGrowGapLeft(self: *const GraphemeGapBuffer, n: usize) bool {
    return self.graphemes_len.canGrowGapLeft(n);
}

pub fn growGapLeft(self: *GraphemeGapBuffer, n: usize) void {
    for (self.graphemes_len.growGapLeft(n)) |grapheme_len| {
        _ = self.buf.growGapLeft(grapheme_len);
    }
}

pub inline fn canGrowGapRight(self: *const GraphemeGapBuffer, n: usize) bool {
    return self.graphemes_len.canGrowGapRight(n);
}

pub fn growGapRight(self: *GraphemeGapBuffer, n: usize) void {
    for (self.graphemes_len.growGapRight(n)) |grapheme_len| {
        _ = self.buf.growGapRight(grapheme_len);
    }
}

// const GraphemeInfo = struct {
//     len: u16,
//     display_width: u8,
// };
