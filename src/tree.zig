const std = @import("std");

const LayoutConstraints = @import("layout_constraints.zig");
const Screen = @import("screen.zig");

const Element = @import("element.zig");

const Tree = @This();

allocator: std.mem.Allocator,

element_handle_store: Element.HandleStore,

elements: std.ArrayList(Element),
child_parent_map: std.ArrayList(Element.Handle),

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!Tree {
    var element_handle_store = try Element.HandleStore.init(allocator, 256);
    errdefer element_handle_store.deinit(allocator);

    var elements = try std.ArrayList(Element).initCapacity(allocator, 256);
    errdefer elements.deinit(allocator);

    var child_parent_map = try std.ArrayList(Element.Handle).initCapacity(allocator, 256);
    errdefer child_parent_map.deinit(allocator);

    return Tree{
        .allocator = allocator,

        .element_handle_store = element_handle_store,

        .elements = elements,
        .child_parent_map = child_parent_map,
    };
}

pub fn deinit(self: *Tree) void {
    for (0..self.element_handle_store.count()) |i| {
        self.elements.items[i].children.deinit(self.allocator);
    }

    self.element_handle_store.deinit(self.allocator);

    self.elements.deinit(self.allocator);
    self.child_parent_map.deinit(self.allocator);
}

pub fn clear(self: *Tree) void {
    for (0..self.element_handle_store.count()) |i| {
        self.elements.items[i].children.clearAndFree(self.allocator);
    }

    self.element_handle_store.clear();

    self.elements.clearRetainingCapacity();
    self.child_parent_map.clearRetainingCapacity();
}

pub inline fn isValid(self: *const Tree, handle: Element.Handle) bool {
    return self.element_handle_store.isValid(handle);
}

pub fn create(self: *Tree, interface: Element.Interface) std.mem.Allocator.Error!Element.Handle {
    const handle = try self.element_handle_store.create(self.allocator);
    errdefer self.element_handle_store.remove(handle);

    const element = blk: {
        if (handle.index < self.elements.capacity) {
            break :blk try self.elements.addOne(self.allocator);
        }
        break :blk &self.elements.items[handle.index];
    };
    try self.child_parent_map.ensureTotalCapacity(self.allocator, self.elements.capacity);

    element.* = Element{
        .interface = interface,
    };

    return handle;
}

pub fn get(self: *const Tree, handle: Element.Handle) *const Element {
    std.debug.assert(self.isValid(handle));
    return &self.elements.allocatedSlice()[handle.index];
}

pub fn getMut(self: *Tree, handle: Element.Handle) *Element {
    std.debug.assert(self.isValid(handle));
    return &self.elements.allocatedSlice()[handle.index];
}

pub fn addChildren(self: *Tree, parent_handle: Element.Handle, children: []const Element.Handle) std.mem.Allocator.Error!void {
    std.debug.assert(self.isValid(parent_handle));
    const element = self.getMut(parent_handle);

    try element.children.ensureUnusedCapacity(self.allocator, children.len);
    for (children) |child| {
        if (!self.isValid(child)) continue;

        self.getMut(child).parent = parent_handle;
        element.children.appendAssumeCapacity(child);
    }
}
