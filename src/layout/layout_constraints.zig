const std = @import("std");

const Element = @import("../tree/element.zig");
const Tree = @import("../tree/tree.zig");

const LayoutConstraint = @This();

pub const zero = LayoutConstraint{
    .height = Constraint{ .fixed = 0 },
    .width = Constraint{ .fixed = 0 },
};

height: Constraint,
width: Constraint,

pub fn fixed(value: u16) LayoutConstraint {
    return LayoutConstraint{
        .height = .{ .fixed = value },
        .width = .{ .fixed = value },
    };
}

pub fn isNull(self: *const LayoutConstraint) bool {
    return self.height.isNull() or self.width.isNull();
}

pub const Constraint = union(enum) {
    fixed: u16,
    viewport_percentage: f32,
    parent_percentage: f32,

    pub fn isNull(self: Constraint) bool {
        switch (self) {
            .fixed => |v| return v == 0,
            .viewport_percentage => |v| return v == 0,
            .parent_percentage => |v| return v == 0,
        }
    }
};
