const std = @import("std");

pub fn IndexT(comptime ParentT: type, comptime T: type) type {
    // we only need the parent type for uniques
    _ = ParentT;

    if (@typeInfo(T) != .int) @compileError("expected T is of type 'int'");

    return enum(T) {
        pub const UnderlyingT = T;

        const Self = @This();

        invalid = std.math.maxInt(T),
        _,

        /// assert the value is not equal to invalid
        pub inline fn from(v: T) Self {
            std.debug.assert(v != comptime Self.invalid.value());
            return @enumFromInt(v);
        }

        pub inline fn value(self: Self) T {
            return @intFromEnum(self);
        }

        pub inline fn prev(self: Self) Self {
            return Self.from(self.value() - 1);
        }

        pub inline fn next(self: Self) Self {
            return Self.from(self.value() + 1);
        }

        pub inline fn decrement(self: Self, n: T) Self {
            return Self.from(self.value() - n);
        }

        pub inline fn increment(self: Self, n: T) Self {
            return Self.from(self.value() + n);
        }

        pub inline fn eql(self: Self, other: Self) bool {
            return self.value() == other.value();
        }
    };
}
