const std = @import("std");
const zttio = @import("zttio");

const Segment = @import("segment.zig");
const Screen = @import("screen.zig");
const ScreenStore = @import("screen_store.zig");

const IndexT = @import("../index.zig").IndexT;

pub const Index = IndexT(Cell, u32);

const Cell = @This();

content: Content = .{ .char = ' ' },
style: ScreenStore.StyleHandle = .invalid,
segment: ScreenStore.SegmentHandle = .invalid,

comptime {
    std.debug.assert(@sizeOf(Cell) == 8);
}

// pub fn eql(self: Cell, other: Cell) bool {
//     if (!self.style.eql(other.style)) return false;
//     if (!self.block.eql(other.block)) return false;
//     if (std.meta.activeTag(self.content) != std.meta.activeTag(other.content)) return false;
//     switch (self.content) {
//         .char => |c| {
//             return c == other.content.char;
//         },
//         .short => |s| {
//             const self_content = s[0 .. std.mem.indexOf(u8, &s, &.{0}) orelse 8];
//             const other_content = other.content.short[0 .. std.mem.indexOf(u8, &other.content.short, &.{0}) orelse 8];
//             return std.mem.eql(self_content, other_content);
//         },
//         .long_local => {
//             @panic("unimplemented");
//         },
//         .long_shared => {
//             @panic("unimplemented");
//         },
//         .wide_continuation => return true,
//     }
// }

pub const shortStringMaxLength = 3;

pub const Content = union(enum) {
    char: u8,
    /// null terminated if not fully used
    short: [shortStringMaxLength]u8,
    long_shared: ScreenStore.StrHandle,
    long_local: Screen.StrIndex,
    wide_continuation,

    /// 'store' only needs to be provided if a 'long_shared' content is given.
    pub inline fn calcWidth(self: Content, screen: *const Screen, store: ?*const ScreenStore) u16 {
        return @intCast(blk: switch (self) {
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
