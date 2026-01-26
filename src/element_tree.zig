const std = @import("std");

const IndexT = @import("index.zig").IndexT;
const HandleStoreT = @import("handles.zig").HandleStoreT;

const ElementStore = HandleStoreT(Element, u32);
pub const ElementHandle = ElementStore.Handle;

pub const Tree = struct {
    allocator: std.mem.Allocator,

    node_store: ElementStore,
    nodes: std.ArrayList(Element),
    children: std.ArrayList(ElementHandle),

    pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!Tree {
        return Tree{
            .allocator = allocator,
            .node_store = try .init(allocator, 256),
            .nodes = try .initCapacity(allocator, 256),
            .children = try .initCapcity(allocator, 256),
        };
    }

    pub fn deinit(self: *Tree, allocator: std.mem.Allocator) void {
        self.node_store.deinit(allocator);
        self.nodes.deinit(allocator);
        self.children.deinit(allocator);
    }
};

pub const Element = struct {
    pub const ChildrenIndex = IndexT(struct {}, u32);

    handle: ElementHandle,
    children_index: ChildrenIndex = .invalid,

    pub fn children(self: Element, tree: *const Tree) []ElementHandle {
        if (self.children_index == .invalid) return &.{};

        const count = tree.children.items[self.children_index].index;
        return tree.children.items[self.children_index + 1 ..][0..count];
    }
};
