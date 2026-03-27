const std = @import("std");

/// The maximum value of the given type is used for representing an invalid index.
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

        pub inline fn dec(self: Self, n: T) Self {
            return Self.from(self.value() - n);
        }

        pub inline fn inc(self: Self, n: T) Self {
            return Self.from(self.value() + n);
        }
    };
}
