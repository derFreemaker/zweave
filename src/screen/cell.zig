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
        self.content.tag != other.content.tag)
    {
        return false;
    }

    switch (self.content.tag) {
        .empty,
        .wide_continuation,
        => return true,

        .char => {
            return self.content.getChar() == other.content.getChar();
        },
        .short => {
            const self_buf = self.content.getShort();
            const self_content = self_buf[0 .. std.mem.indexOf(u8, &self_buf, &.{0}) orelse Cell.shortStringMaxLength];

            const other_buf = other.content.getShort();
            const other_content = other_buf[0 .. std.mem.indexOf(u8, &other_buf, &.{0}) orelse Cell.shortStringMaxLength];

            return std.mem.eql(u8, self_content, other_content);
        },
        .long_local => {
            const self_content = screen.getStr(self.content.getLongLocal());
            const other_content = other_screen.getStr(other.content.getLongLocal());
            return std.mem.eql(u8, self_content, other_content);
        },
        .long_shared => {
            return self.content.getLongShared().eql(other.content.getLongShared());
        },
    }
}

pub const shortStringMaxLength = 3;

// pub const Content = union(enum) {
//     empty: void,
//     char: u8,
//     /// null terminated if not fully used
//     short: [shortStringMaxLength]u8,
//     long_local: Screen.StrIndex, // u16
//     long_local_2: Screen.StrIndex, // u16 + 0xFFFF -> u32
//     long_shared: ScreenStore.StrHandle, // u16
//     long_shared_2: ScreenStore.StrHandle, // u16 + 0xFFFF -> u32
//     wide_continuation: void,

//     /// 'store' only needs to be provided if a 'long_shared' content is given.
//     pub inline fn calcWidth(self: Content, screen: *const Screen, store: ?*const ScreenStore) u16 {
//         return @intCast(blk: switch (self) {
//             .empty => break :blk 1,
//             .char => break :blk 1,
//             .short => |short| break :blk screen.strWidth(&short),
//             .long_local => |index| break :blk screen.strWidth(screen.strs.items[index.value()]),
//             .long_shared => |handle| {
//                 if (store == null) @panic("store was null, event though a 'long_shared' cell content was provided");

//                 const str = store.?.getStr(handle);
//                 break :blk screen.strWidth(str);
//             },
//             .wide_continuation => break :blk 0,
//         });
//     }
// };

pub const Content = packed struct {
    pub const Tag = enum(u8) {
        empty,
        char,
        short,
        long_local,
        long_shared,
        wide_continuation,
    };

    tag: Tag,
    payload: u24,

    pub const empty = Content{
        .tag = .empty,
        .payload = 0,
    };

    pub inline fn char(c: u8) Content {
        return Content{
            .tag = .char,
            .payload = c,
        };
    }

    pub inline fn getChar(self: Content) u8 {
        std.debug.assert(self.tag == .char);
        return @intCast(self.payload & 0xFF);
    }

    /// null terminated if not fully used
    pub inline fn short(bytes: [shortStringMaxLength]u8) Content {
        const payload: u24 = @as(u24, bytes[0]) |
            (@as(u24, bytes[1]) << 8) |
            (@as(u24, bytes[2]) << 16);

        return Content{
            .tag = .short,
            .payload = payload,
        };
    }

    /// null terminated if not fully used
    pub inline fn getShort(self: Content) [shortStringMaxLength]u8 {
        std.debug.assert(self.tag == .short);
        return .{
            @intCast(self.payload & 0xFF),
            @intCast((self.payload >> 8) & 0xFF),
            @intCast((self.payload >> 16) & 0xFF),
        };
    }

    pub inline fn long_local(index: Screen.StrIndex) Content {
        return Content{
            .tag = .long_local,
            .payload = index.value(),
        };
    }

    pub inline fn getLongLocal(self: Content) Screen.StrIndex {
        std.debug.assert(self.tag == .long_local);

        comptime std.debug.assert(Screen.StrIndex.UnderlyingT == u24);
        return Screen.StrIndex.from(self.payload);
    }

    pub inline fn long_shared(handle: ScreenStore.StrHandle) Content {
        return Content{
            .tag = .long_shared,
            .payload = handle.index,
        };
    }

    pub inline fn getLongShared(self: Content) ScreenStore.StrHandle {
        std.debug.assert(self.tag == .long_shared);

        comptime std.debug.assert(ScreenStore.StrHandle.UnderlyingT == u24);
        comptime std.debug.assert(ScreenStore.StrHandle.Safety == .unsafe);
        return ScreenStore.StrHandle{ .index = self.payload, .generation = void{} };
    }

    pub const wide_continuation = Content{
        .tag = .wide_continuation,
        .payload = 0,
    };

    pub inline fn calcWidth(self: Content, screen: *const Screen, store: ?*const ScreenStore) u16 {
        switch (self.tag) {
            .empty => return 1,
            .char => return 1,
            .short => {
                const buf = self.getShort();
                const str = buf[0 .. std.mem.indexOf(u8, &buf, &.{0}) orelse shortStringMaxLength];
                return @intCast(screen.strWidth(str));
            },
            .long_local => {
                const str = screen.getStr(self.getLongLocal().value());
                return @intCast(screen.strWidth(str));
            },
            .long_shared => {
                if (store == null) @panic("store was null, even though a 'long_shared' cell content was provided");

                const str = store.?.getStr(self.getLongShared());
                return @intCast(screen.strWidth(str));
            },
            .wide_continuation => return 0,
        }
    }
};

comptime {
    std.debug.assert(@sizeOf(Content) == 4);
}
