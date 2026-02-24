const std = @import("std");
const zttio = @import("zttio");

const IndexT = @import("index.zig").IndexT;
const Styling = @import("styling.zig");

const Cell = @This();

pub const Index = IndexT(Cell, u32);

content: Content = .{ .char = ' ' },
style: Styling.Index = .invalid,
block: Segment.Index = .invalid,

comptime {
    std.debug.assert(@sizeOf(Cell) == 16);
}

pub fn eql(self: Cell, other: Cell, self_str_pool: []const u8, other_str_pool: []const u8) bool {
    if (!self.style.eql(other.style)) return false;
    if (!self.block.eql(other.block)) return false;

    if (std.meta.activeTag(self) != std.meta.activeTag(other)) return false;
    switch (self.content) {
        .char => |c| {
            return c == other.content.char;
        },
        .short => |s| {
            const self_content = s[0 .. std.mem.indexOf(u8, &s, &.{0}) orelse 8];
            const other_content = other.content.short[0 .. std.mem.indexOf(u8, &other.content.short, &.{0}) orelse 8];
            return std.mem.eql(self_content, other_content);
        },
        .long => |l| {
            if (l.end - l.start != other.content.long.end - other.content.long.start) return false;
            return std.mem.eql(u8, l.get(self_str_pool), other.content.long.get(other_str_pool));
        },
        .wide_continuation => return true,
    }
}

// we can use up to 11 bytes for data with tag thats 12 bytes
// since we use at least 8 bytes for data and get padded up to 12 bytes anyway
pub const Content = union(enum) {
    char: u8,
    /// null terminated if not fully used
    short: [11]u8,
    long: struct {
        start: u32,
        end: u32,

        pub inline fn get(self: @This(), buf: []const u8) []const u8 {
            std.debug.assert(buf.len >= self.end);
            return buf[self.start..self.end];
        }
    },
    wide_continuation,
};

pub const Segment = struct {
    pub const Index = IndexT(Segment, u16);

    hyperlink: ?zttio.ctlseqs.Hyperlink = null,

    pub fn begin(self: *const Segment, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.hyperlink) |hyperlink| {
            try hyperlink.introduce(writer);
        }
    }

    pub fn end(self: *const Segment, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.hyperlink) |_| {
            try writer.writeAll(zttio.ctlseqs.Hyperlink.close);
        }
    }
};
