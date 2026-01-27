const std = @import("std");

const Screen = @import("screen.zig");
const IndexT = @import("index.zig").IndexT;
const HandleStoreT = @import("handles.zig").HandleStoreT;

const LayoutConstraints = @import("layout_constraints.zig");

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

    pub fn createElement(self: *Tree, ptr: *anyopaque, vtable: *const Element.VTable) std.mem.Allocator.Error!ElementIndex {
        // return try self.element_store.create(self.allocator);

        const index = ElementIndex.from(self.elements.items.len);
        const element = try self.elements.addOne(self.allocator);
        errdefer _ = self.elements.pop();
        element.* = Element{
            .ptr = ptr,
            .vtable = vtable,
        };

        return index;
    }

    pub fn addChildren(self: *Tree, element: ElementIndex, children: []ElementIndex) std.mem.Allocator.Error!void {
        try self.extra.ensureUnusedCapacity(self.allocator, children.len + 1);

        self.elements.items[element.value()].children_index = Element.ChildrenIndex.from(self.extra.items.len);
        self.extra.appendAssumeCapacity(children.len);
        self.extra.appendSliceAssumeCapacity(@as([]ElementIndex.UnderlyingT, @ptrCast(children)));
    }
};

pub const Element = struct {
    pub const ChildrenIndex = IndexT(struct {}, u32);

    pub const VTable = struct {
        registerInLayout: ?*const fn (self_ptr: *anyopaque, tree: *Tree) std.mem.Allocator.Error!void = null,
        getLayoutConstraints: *const fn (self_ptr: *anyopaque) LayoutConstraints,
        calcLayout: ?*const fn (self_ptr: *anyopaque, available: SmallVec2) SmallVec2 = null,
        draw: *const fn (self_ptr: *anyopaque, view: Screen.View) std.mem.Allocator.Error!void = null,
    };

    ptr: *anyopaque,
    vtable: *const VTable,
    // handle: ElementHandle,
    children_index: ChildrenIndex = .invalid,

    pub fn children(self: Element, tree: *const Tree) []ElementIndex {
        if (self.children_index == .invalid) return &.{};

        const count = tree.extra.items[self.children_index];
        const childs: []ElementIndex = @ptrCast(tree.extra.items[self.children_index + 1 ..][0..count]);
        return childs;
    }
};

pub const SmallVec2 = struct {
    x: u16,
    y: u16,
};
