const std = @import("std");

const IndexT = @import("index.zig").IndexT;
const HandleStoreT = @import("handles.zig").HandleStoreT;

const ElementIndex = IndexT(Element, u32);

// const ElementStore = HandleStoreT(Element, u32);
// pub const ElementHandle = ElementStore.Handle;

pub const Tree = struct {
    allocator: std.mem.Allocator,

    // element_store: ElementStore,
    elements: std.ArrayList(Element),
    extra: std.ArrayList(ElementIndex.UnderlyingT),

    pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!Tree {
        // var element_store = try ElementStore.init(allocator, 256);
        // errdefer element_store.deinit(allocator);

        var elements = try std.ArrayList(Element).initCapacity(allocator, 256);
        errdefer elements.deinit(allocator);

        var children = try std.ArrayList(ElementIndex.UnderlyingT).initCapacity(allocator, 256);
        errdefer children.deinit(allocator);

        return Tree{
            .allocator = allocator,
            // .element_store = element_store,
            .elements = elements,
            .extra = children,
        };
    }

    pub fn deinit(self: *Tree, allocator: std.mem.Allocator) void {
        // self.element_store.deinit(allocator);
        self.elements.deinit(allocator);
        self.extra.deinit(allocator);
    }

    pub fn clear(self: *Tree) void {
        // self.element_store.clear();
        self.elements.clearRetainingCapacity();
        self.extra.clearRetainingCapacity();
    }

    pub fn createElement(self: *Tree, ptr: *anyopaque, children: []ElementIndex) std.mem.Allocator.Error!ElementIndex {
        // return try self.element_store.create(self.allocator);

        var i: usize = 0;
        errdefer self.extra.items.len -= i;
        if (children.len > 0) {
            try self.extra.append(self.allocator, children.len);
            errdefer self.extra.pop();

            for (children) |child| {
                errdefer self.extra.items.len -= i;
                try self.extra.append(self.allocator, child.value());
                i += 1;
            }

            i += 1;
        }

        const index = ElementIndex.from(self.elements.items.len);
        const element = try self.elements.addOne();
        errdefer _ = self.elements.pop();
        element.* = Element{
            .ptr = ptr,
            .children_index = if (children.len == 0)
                .invalid
            else
                Element.ChildrenIndex.from(self.extra.items.len - i),
        };

        return index;
    }
};

pub const Element = struct {
    pub const ChildrenIndex = IndexT(struct {}, u32);

    ptr: *anyopaque,
    // handle: ElementHandle,
    children_index: ChildrenIndex = .invalid,

    pub fn children(self: Element, tree: *const Tree) []ElementIndex {
        if (self.children_index == .invalid) return &.{};

        const count = tree.extra.items[self.children_index].index;
        return tree.extra.items[self.children_index + 1 ..][0..count];
    }
};
