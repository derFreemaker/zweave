const std = @import("std");
const zttio = @import("zttio");

const IndexT = @import("../common/index.zig").IndexT;
const Segment = @import("segment.zig");
const Screen = @import("screen.zig");
const ScreenStore = @import("screen_store.zig");

pub const Index = IndexT(Cell, u32);

const Cell = @This();

content: Content = .empty,
style: ScreenStore.StyleHandle = .invalid,
segment: ScreenStore.SegmentHandle = .invalid,

comptime {
    std.debug.assert(@sizeOf(Cell) == 8);
}

pub fn eql(self: *const Cell, screen: *const Screen, other: *const Cell, other_screen: *const Screen) bool {
    if (!self.style.eql(other.style) or
        !self.segment.eql(other.segment) or
        std.meta.activeTag(self.content) != std.meta.activeTag(other.content))
    {
        return false;
    }

    switch (self.content) {
        .empty,
        .wide_continuation,
        => return true,

        .char => {
            return self.content.char == other.content.char;
        },
        .short => {
            const self_content = self.content.short[0 .. std.mem.indexOf(u8, &self.content.short, &.{0}) orelse 8];
            const other_content = other.content.short[0 .. std.mem.indexOf(u8, &other.content.short, &.{0}) orelse 8];
            return std.mem.eql(u8, self_content, other_content);
        },
        .long_local => {
            const self_content = screen.getStr(self.content.long_local);
            const other_content = other_screen.getStr(other.content.long_local);
            return std.mem.eql(u8, self_content, other_content);
        },
        .long_shared => {
            return self.content.long_shared.eql(other.content.long_shared);
        },
    }
}

pub const shortStringMaxLength = 3;

pub const Content = union(enum) {
    empty,
    char: u8,
    /// null terminated if not fully used
    short: [shortStringMaxLength]u8,
    long_shared: ScreenStore.StrHandle,
    long_local: Screen.StrIndex,
    wide_continuation,

    /// 'store' only needs to be provided if a 'long_shared' content is given.
    pub inline fn calcWidth(self: Content, screen: *const Screen, store: ?*const ScreenStore) u16 {
        return @intCast(blk: switch (self) {
            .empty => break :blk 0,
            .char => break :blk 1,
            .short => |short| break :blk screen.strWidth(&short),
            .long_local => |index| break :blk screen.strWidth(screen.strs.items[index.value()]),
            .long_shared => |handle| {
                if (store == null) @panic("store was null, event though a 'long_shared' cell content was provided");

                const str = store.?.getStr(handle);
                break :blk screen.strWidth(str);
            },
            .wide_continuation => break :blk 0,
        });
    }
};
