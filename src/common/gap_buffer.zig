const std = @import("std");

pub fn GapBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        buf: []T,
        cur_idx: usize,
        gap_size: usize,

        pub const empty = Self{
            .buf = &.{},
            .cur_idx = 0,
            .gap_size = 0,
        };

        pub fn initCapacity(allocator: std.mem.Allocator, n: usize) std.mem.Allocator.Error!Self {
            const buf = try allocator.alloc(T, n);
            errdefer allocator.free(buf);

            return Self{
                .buf = buf,
                .cur_idx = 0,
                .gap_size = buf.len,
            };
        }

        pub inline fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.buf);
        }

        pub inline fn clearAndFree(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.buf);
            self.* = .empty;
        }

        pub inline fn clearRetainingCapacity(self: *Self) void {
            self.cur_idx = 0;
            self.gap_size = self.buf.len;
        }

        pub inline fn len(self: *const Self) usize {
            return self.buf.len - self.gap_size;
        }

        pub inline fn firstHalf(self: *const Self) []const T {
            return self.buf[0..self.cur_idx];
        }

        pub inline fn firstHalfMut(self: *Self) []T {
            return self.buf[0..self.cur_idx];
        }

        pub inline fn secondHalf(self: *const Self) []const T {
            return self.buf[self.cur_idx + self.gap_size ..];
        }

        pub inline fn secondHalfMut(self: *Self) []T {
            return self.buf[self.cur_idx + self.gap_size ..];
        }

        inline fn gap(self: *Self) []T {
            return self.buf[self.cur_idx .. self.cur_idx + self.gap_size];
        }

        pub fn grow(self: *Self, allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
            const old_size = self.buf.len;
            const new_size = self.buf.len +| self.buf.len / 2;

            const second_half_len = self.secondHalf().len;

            if (allocator.remap(self.buf, new_size)) |new_buf| {
                @memmove(new_buf[new_size - second_half_len ..], new_buf[old_size - second_half_len .. old_size]);
                self.buf = new_buf;
            } else {
                const new_buf = try allocator.alloc(T, new_size);

                @memcpy(new_buf[0..self.cur_idx], self.firstHalf());
                @memcpy(new_buf[new_size - second_half_len ..], self.secondHalf());

                allocator.free(self.buf);
                self.buf = new_buf;
            }

            self.gap_size = new_size - old_size;
        }

        pub fn insert(self: *Self, allocator: std.mem.Allocator, item: T) std.mem.Allocator.Error!void {
            if (self.gap_size < 1) {
                @branchHint(.unlikely);
                try self.grow(allocator);
            }

            self.gap()[0] = item;
            self.cur_idx += 1;
            self.gap_size -= 1;
        }

        pub fn insertSlice(self: *Self, allocator: std.mem.Allocator, slice: []const T) std.mem.Allocator.Error!void {
            if (self.gap_size < slice.len) {
                @branchHint(.unlikely);
                try self.grow(allocator);
            }

            @memcpy(self.gap()[0..slice.len], slice);
            self.cur_idx += slice.len;
            self.gap_size -= slice.len;
        }

        pub inline fn canMoveGapLeft(self: *const Self, n: usize) bool {
            return n <= self.cur_idx;
        }

        pub fn moveGapLeft(self: *Self, n: usize) ?[]T {
            if (!self.canMoveGapLeft(n)) {
                @branchHint(.cold);
                return null;
            }
            const new_idx = self.cur_idx - n;

            const src = self.buf[new_idx..self.cur_idx];
            const dst = self.buf[new_idx + self.gap_size .. new_idx + self.gap_size + src.len];
            @memmove(dst, src);

            self.cur_idx = new_idx;
            return dst;
        }

        pub inline fn canMoveGapRight(self: *const Self, n: usize) bool {
            return n <= self.secondHalf().len;
        }

        pub fn moveGapRight(self: *Self, n: usize) ?[]T {
            if (!self.canMoveGapRight(n)) {
                @branchHint(.cold);
                return null;
            }
            const new_idx = self.cur_idx + n;

            const src = self.buf[self.cur_idx + self.gap_size .. new_idx + self.gap_size];
            const dst = self.buf[self.cur_idx .. self.cur_idx + src.len];
            @memmove(dst, src);

            self.cur_idx = new_idx;
            return dst;
        }

        pub inline fn canGrowGapLeft(self: *const Self, n: usize) bool {
            return self.cur_idx >= n;
        }

        /// the returned slice is a subslice inside the gap
        pub fn growGapLeft(self: *Self, n: usize) []T {
            std.debug.assert(self.canGrowGapLeft(n));

            self.cur_idx -= n;
            self.gap_size += n;
            return self.buf[self.cur_idx .. self.cur_idx + n];
        }

        pub inline fn canGrowGapRight(self: *const Self, n: usize) bool {
            return self.secondHalf().len >= n;
        }

        /// the returned slice is a subslice inside the gap
        pub fn growGapRight(self: *Self, n: usize) []T {
            std.debug.assert(self.canGrowGapRight(n));

            self.gap_size += n;
            return self.buf[self.cur_idx + self.gap_size - n .. self.cur_idx + self.gap_size];
        }

        pub fn toOwnedSlice(self: *const Self, allocator: std.mem.Allocator) std.mem.Allocator.Error![]T {
            const first_half = self.firstHalf();
            const second_half = self.secondHalf();

            const buf = try allocator.alloc(T, self.len());
            @memcpy(buf[0..first_half.len], first_half);
            @memcpy(buf[first_half.len..], second_half);

            return buf;
        }
    };
}

test GapBuffer {
    const allocator = std.testing.allocator;

    var gap_buf: GapBuffer(u8, .{}) = .empty;
    defer gap_buf.deinit(allocator);

    try gap_buf.insertSlice(allocator, "abc");
    try std.testing.expectEqualStrings("abc", gap_buf.firstHalf());
    try std.testing.expectEqualStrings("", gap_buf.secondHalf());

    try std.testing.expect(gap_buf.moveGapLeft(2) != null);
    try std.testing.expectEqualStrings("a", gap_buf.firstHalf());
    try std.testing.expectEqualStrings("bc", gap_buf.secondHalf());

    try std.testing.expect(gap_buf.moveGapRight(1) != null);
    try std.testing.expectEqualStrings("ab", gap_buf.firstHalf());
    try std.testing.expectEqualStrings("c", gap_buf.secondHalf());

    try gap_buf.insert(allocator, ' ');
    try std.testing.expectEqualStrings("ab ", gap_buf.firstHalf());
    try std.testing.expectEqualStrings("c", gap_buf.secondHalf());

    try std.testing.expect(gap_buf.growGapLeft(1).len == 1);
    try std.testing.expectEqualStrings("ab", gap_buf.firstHalf());
    try std.testing.expectEqualStrings("c", gap_buf.secondHalf());
    try std.testing.expectEqual(2, gap_buf.cur_idx);

    try std.testing.expect(gap_buf.growGapRight(1).len == 1);
    try std.testing.expectEqualStrings("ab", gap_buf.firstHalf());
    try std.testing.expectEqualStrings("", gap_buf.secondHalf());
    try std.testing.expectEqual(2, gap_buf.cur_idx);
}
