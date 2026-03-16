const std = @import("std");

const ScreenVec = @import("../common/screen_vec.zig");
const LayoutConstraints = @import("layout_constraints.zig");
const Element = @import("element.zig");
const Event = @import("../event.zig").Event;

const Tree = @This();

allocator: std.mem.Allocator,

handle_store: Element.HandleStore,

elements: []Element,
layout_data: []LayoutData,

focused_element: Element.Handle = .invalid,

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!Tree {
    var element_handle_store = try Element.HandleStore.init(allocator, 256);
    errdefer element_handle_store.deinit(allocator);

    const elements = try allocator.alloc(Element, 256);
    errdefer allocator.free(elements);

    const layout_data = try allocator.alloc(LayoutData, 256);
    errdefer allocator.free(layout_data);
    @memset(layout_data, LayoutData.zero);

    return Tree{
        .allocator = allocator,

        .handle_store = element_handle_store,

        .elements = elements,
        .layout_data = layout_data,

        .focused_element = .invalid,
    };
}

pub fn deinit(self: *Tree) void {
    for (0..self.handle_store.maxUsed()) |i| {
        self.elements[i].children.deinit(self.allocator);
    }

    self.handle_store.deinit(self.allocator);

    self.allocator.free(self.elements);
    self.allocator.free(self.layout_data);
}

pub fn clear(self: *Tree) void {
    for (0..self.handle_store.count()) |i| {
        self.elements[i].children.clearAndFree(self.allocator);
    }

    self.handle_store.clear();
}

fn growBuffers(self: *Tree) std.mem.Allocator.Error!void {
    const new_size = self.elements.len + self.elements.len;

    if (self.allocator.remap(self.elements, new_size)) |new_elements| {
        self.elements = new_elements;
    } else {
        const new_elements = try self.allocator.alloc(Element, new_size);
        errdefer self.allocator.free(new_elements);

        @memcpy(new_elements[0..self.elements.len], self.elements);
        self.allocator.free(self.elements);
        self.elements = new_elements;
    }

    if (self.allocator.remap(self.layout_data, new_size)) |new_layout_data| {
        self.layout_data = new_layout_data;
    } else {
        const new_layout_data = try self.allocator.alloc(LayoutData, new_size);
        errdefer self.allocator.free(new_layout_data);

        @memcpy(new_layout_data[0..self.layout_data.len], self.layout_data);
        self.allocator.free(self.layout_data);
        self.layout_data = new_layout_data;
    }
}

pub inline fn isValid(self: *const Tree, handle: Element.Handle) bool {
    return self.handle_store.isValid(handle);
}

pub fn create(self: *Tree, interface: Element.Interface) std.mem.Allocator.Error!Element.Handle {
    const handle = try self.handle_store.create(self.allocator);
    errdefer self.handle_store.destroy(handle);

    const element: *Element = blk: {
        if (handle.index > self.elements.len) {
            try self.growBuffers();
        }
        break :blk &self.elements[handle.index];
    };

    element.* = Element{
        .interface = interface,
    };

    return handle;
}

pub fn destroy(self: *Tree, handle: Element.Handle) void {
    if (!self.isValid(handle)) return;

    self.layout_data[handle.index] = .zero;
    self.handle_store.destroy(handle);
}

pub fn get(self: *const Tree, handle: Element.Handle) *const Element {
    std.debug.assert(self.isValid(handle));
    return &self.elements[handle.index];
}

pub fn getMut(self: *Tree, handle: Element.Handle) *Element {
    std.debug.assert(self.isValid(handle));
    return &self.elements[handle.index];
}

pub fn getLayoutData(self: *const Tree, handle: Element.Handle) *const LayoutData {
    std.debug.assert(self.isValid(handle));
    return &self.layout_data[handle.index];
}

pub fn getLayoutDataMut(self: *Tree, handle: Element.Handle) *LayoutData {
    std.debug.assert(self.isValid(handle));
    return &self.layout_data[handle.index];
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

pub fn markDirty(self: *Tree, handle: Element.Handle) void {
    if (!self.isValid(handle)) return;

    const element = self.getMut(handle);
    element.isDirty = true;
    if (element.parent == .invalid) {
        return;
    }

    var cur_parent_element_handle: Element.Handle = element.parent;
    while (cur_parent_element_handle != .invalid) |parent_element_handle| {
        const parent_element = self.getMut(parent_element_handle);
        if (parent_element.childIsDirty) break;

        parent_element.childIsDirty = true;
        cur_parent_element_handle = parent_element.parent;
    }
}

pub inline fn isFocused(self: *const Tree, handle: Element.Handle) bool {
    return self.focused_element.eql(handle);
}

pub inline fn removeFocus(self: *Tree) void {
    self.focused_element = .invalid;
}

pub fn setFocus(self: *Tree, handle: Element.Handle) Element.EventError!void {
    if (self.focused_element.eql(handle)) return;

    self.focused_element = handle;
    try self.get(handle).interface.onEvent(&Element.EventContext{
        .tree = self,

        .handle = handle,

        .event = &.focus_in,
    });
}

pub const LayoutData = struct {
    pub const zero = LayoutData{
        .pos = .zero,
        .size = .zero,
    };

    pos: ScreenVec,
    size: ScreenVec,
};
