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
