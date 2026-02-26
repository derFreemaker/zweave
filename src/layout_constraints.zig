const std = @import("std");

const Element = @import("element.zig");
const Tree = @import("tree.zig");

const LayoutConstraint = @This();

height: Constraint,
width: Constraint,

pub const Constraint = union(enum) {
    fixed: u16,
    percentage: f32,
    // range: Range,

    pub const Range = struct {
        min: ?u16 = null,
        max: ?u16 = null,
    };
};
