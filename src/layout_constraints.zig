const std = @import("std");

const Element = @import("element.zig");
const Tree = @import("tree.zig");

const LayoutConstraint = @This();

height: Constraint,
width: Constraint,

pub const Constraint = union(enum) {
    full,
    fixed: u16,
    percentage: f32,
    range: Range,

    pub const Range = struct {
        min: ?u16 = null,
        max: ?u16 = null,
    };
};

pub fn computeLayoutConstraint(allocator: std.mem.Allocator, tree: *const Tree, elements_handles: []Element.Handle, opts: ComputeLayoutConstraintOptions) std.mem.Allocator.Error!LayoutConstraint {
    _ = opts;

    var constraints: [elements_handles.len]LayoutConstraint = undefined;
    for (elements_handles, 0..) |element_handle, i| {
        const element = tree.get(element_handle);
        constraints[i] = element.interface.vtable.getLayoutConstraints(&Element.GetLayoutConstraintsContext{
            .allocator = allocator,
            .tree = tree,

            .self = element,
            .self_handle = element_handle,
        });
    }

    @panic("unfinished");
}

pub const ComputeLayoutConstraintOptions = struct {};

pub fn computeLayout(allocator: std.mem.Allocator, tree: *const Tree, elements_handles: []Element.Handle, opts: ComputeLayoutOptions) std.mem.Allocator.Error!Element.SmallVec2 {
    _ = allocator;
    _ = tree;
    _ = elements_handles;
    _ = opts;

    @panic("unfinished");
}

pub const ComputeLayoutOptions = struct {
    available: Element.SmallVec2,
};
