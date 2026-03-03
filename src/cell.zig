const std = @import("std");
const zttio = @import("zttio");

const ScreenStore = @import("screen/screen_store.zig");

const IndexT = @import("index.zig").IndexT;
const Styling = @import("styling.zig");

const Cell = @This();

pub const Index = IndexT(Cell, u32);

content: Content = .{ .char = ' ' },
style: ScreenStore.StyleHandle = .invalid,
block: ScreenStore.SegmentHandle = .invalid,

comptime {
    std.debug.assert(@sizeOf(Cell) == 8);
}

pub fn eql(self: Cell, other: Cell, self_str_pool: []const u8, other_str_pool: []const u8) bool {
    if (!self.style.eql(other.style)) return false;
    if (!self.block.eql(other.block)) return false;

    if (std.meta.activeTag(self.content) != std.meta.activeTag(other.content)) return false;
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

pub const shortStringMaxLength = 3;

pub const Content = union(enum) {
    char: u8,
    /// null terminated if not fully used
    short: [shortStringMaxLength]u8,
    // long: ScreenStore.StrHandle,
    wide_continuation,
};

pub const Segment = struct {
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
