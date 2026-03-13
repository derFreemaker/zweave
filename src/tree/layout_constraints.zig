const std = @import("std");

const Element = @import("element.zig");
const Tree = @import("tree.zig");

const LayoutConstraint = @This();

height: Constraint,
width: Constraint,

pub fn isNull(self: *const LayoutConstraint) bool {
    return self.height.isNull() or self.width.isNull();
}

pub const Constraint = union(enum) {
    fixed: u16,
    percentage: f32,
    // range: Range,

    pub fn isNull(self: Constraint) bool {
        switch (self) {
            .fixed => |fixed| return fixed == 0,
            .percentage => |perc| return perc == 0,
        }
    }

    pub const Range = struct {
        min: ?u16 = null,
        max: ?u16 = null,
    };
};
