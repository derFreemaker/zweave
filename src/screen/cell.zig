const std = @import("std");
const builtin = @import("builtin");

const zttio = @import("zttio");

const IndexT = @import("../common/index.zig").IndexT;
const Screen = @import("screen.zig");
const ScreenStore = @import("screen_store.zig");
const Segment = @import("segment.zig");
const Styling = @import("styling.zig").Styling;

pub const Index = IndexT(Cell, u32);

const Cell = @This();

comptime {
    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
        std.debug.assert(@sizeOf(Cell) == 32);
    } else {
        std.debug.assert(@sizeOf(Cell) == 16);
    }
}

content: Content = .empty,
styling: ScreenStore.StylingHandle = .invalid,
segment: ScreenStore.SegmentHandle = .invalid,

pub fn eql(self: *const Cell, screen: *const Screen, other: *const Cell, other_screen: *const Screen) bool {
    if (!self.styling.eql(other.styling) or
        !self.segment.eql(other.segment) or
        std.meta.activeTag(self.content) != std.meta.activeTag(other.content))
    {
        return false;
    }

    switch (self.content) {
        .empty,
        .skipped,
        => return true,

        .char => {
            return self.content.char == other.content.char;
        },
        .short => {
            return std.mem.eql(u8, self.content.readShort(), other.content.readShort());
        },
        .frame_long => {
            const self_content = screen.getStr(self.content.frame_long);
            const other_content = other_screen.getStr(other.content.frame_long);

            return std.mem.eql(u8, self_content, other_content);
        },
        .shared_long => {
            if (screen.store == other_screen.store) {
                return self.content.shared_long.eql(other.content.shared_long);
            }

            const self_content = screen.store.getStr(self.content.shared_long).*;
            const other_content = other_screen.store.getStr(other.content.shared_long).*;
            return std.mem.eql(u8, self_content, other_content);
        },
    }
}

pub const CONTENT_SHORT_STR_MAX_LENGTH = 7;

pub const Content = union(enum) {
    empty: void,
    char: u8,
    /// null terminated if not fully used
    short: [CONTENT_SHORT_STR_MAX_LENGTH]u8,
    /// lives only during one frame
    frame_long: Screen.StrIndex,
    shared_long: ScreenStore.StrHandle,
    skipped: void,

    pub inline fn readShort(self: *const Content) []const u8 {
        std.debug.assert(self.* == .short);
        const end = std.mem.indexOf(u8, &self.short, &.{0}) orelse CONTENT_SHORT_STR_MAX_LENGTH;
        return self.short[0..end];
    }

    pub inline fn calcWidth(self: Content, screen: *const Screen) u16 {
        return @intCast(blk: switch (self) {
            .empty => break :blk 1,
            .char => break :blk 1,
            .short => break :blk screen.strWidth(self.readShort()),
            .frame_long => |index| break :blk screen.strWidth(screen.strs.items[index.value()]),
            .shared_long => |handle| {
                const str = screen.store.getStr(handle).*;
                break :blk screen.strWidth(str);
            },
            .skipped => break :blk 0,
        });
    }

    pub fn from(str: []const u8) Content {
        comptime std.debug.assert(CONTENT_SHORT_STR_MAX_LENGTH > 2);

        return switch (str.len) {
            0 => .empty,
            1 => Content{ .char = str[0] },
            2...CONTENT_SHORT_STR_MAX_LENGTH - 1 => {
                var buf: [CONTENT_SHORT_STR_MAX_LENGTH]u8 = undefined;
                buf[str.len] = 0;
                @memcpy(buf[0..str.len], str);

                return Content{ .short = buf };
            },
            CONTENT_SHORT_STR_MAX_LENGTH => {
                var buf: [CONTENT_SHORT_STR_MAX_LENGTH]u8 = undefined;
                @memcpy(&buf, str);

                return Content{ .short = buf };
            },
            else => {
                std.debug.panic("str ('{s}') len: {d} > max short length: {d}", .{ str, str.len, CONTENT_SHORT_STR_MAX_LENGTH });
            },
        };
    }
};

comptime {
    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
        std.debug.assert(@sizeOf(Content) == 16);
    } else {
        std.debug.assert(@sizeOf(Content) == 8);
    }
}
