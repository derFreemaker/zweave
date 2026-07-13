const std = @import("std");

/// The maximum value of the given type is used for representing an invalid index.
pub fn IndexT(comptime ParentT: type, comptime T: type) type {
    // we only need the parent type for uniques
    _ = ParentT;

    if (@typeInfo(T) != .int) @compileError("expected T is of type 'int'");

    return enum(T) {
        pub const UnderlyingT = T;

        const Self = @This();

        invalid = 0,
        _,

        pub inline fn isInvalid(self: Self) bool {
            return self.value() == comptime Self.invalid.value();
        }

        pub inline fn from(v: T) Self {
            return @enumFromInt(v);
        }

        pub inline fn value(self: Self) T {
            return @intFromEnum(self);
        }

        /// Does a saturating subtraction.
        pub inline fn sub(self: Self, n: T) Self {
            return Self.from(self.value() -| n);
        }

        pub inline fn add(self: Self, n: T) Self {
            return Self.from(self.value() + n);
        }

        pub inline fn inc(self: *Self, n: T) void {
            self.* = .from(self.value() + n);
        }

        pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print("{d}", .{self.value()});
        }
    };
}
