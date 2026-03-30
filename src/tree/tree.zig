const std = @import("std");

const ScreenVec = @import("../common/screen_vec.zig");
const LayoutConstraints = @import("../layout/layout_constraints.zig");
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

fn grow(self: *Tree) std.mem.Allocator.Error!void {
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
    return !handle.isInvalid() and self.handle_store.isValid(handle);
}

pub fn create(self: *Tree, interface: Element.Interface) Element.RegisterError!Element.Handle {
    const handle = try self.handle_store.create(self.allocator);
    errdefer self.handle_store.destroy(handle);

    const element: *Element = blk: {
        if (handle.index > self.elements.len) {
            try self.grow();
        }
        break :blk &self.elements[handle.index];
    };

    element.* = Element{
        .interface = interface,
    };

    if (interface.hasRegister()) {
        try interface.register(&Element.RegisterContext{
            .tree = self,

            .handle = handle,
        });
    }

    return handle;
}

pub fn destroy(self: *Tree, handle: Element.Handle) void {
    if (!self.isValid(handle)) return;
    self.removeChild(handle);

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

pub const LayoutData = struct {
    pub const zero = LayoutData{
        .pos = .zero,
        .size = .zero,
    };

    /// relative to parent element
    pos: ScreenVec,

    size: ScreenVec,
};

pub fn insertChildren(self: *Tree, parent_handle: Element.Handle, idx: usize, children: []const Element.Handle) void {
    std.debug.assert(self.isValid(parent_handle));
    if (children.len == 0) return;

    const parent = self.getMut(parent_handle);
    var prev_child: Element.Handle = blk: {
        if (idx == 0) break :blk .invalid;

        var cur_child = if (!parent.first_child.isInvalid()) break :blk .invalid else parent.first_child;
        for (0..idx) |_| {
            cur_child = self.get(cur_child).next_sibling;
            if (cur_child.isInvalid()) break :blk .invalid;
        }
        break :blk cur_child;
    };
    std.debug.assert(prev_child.isInvalid() or self.isValid(prev_child));

    const next_child: Element.Handle = if (prev_child.isInvalid()) .invalid else self.get(prev_child).next_sibling;
    std.debug.assert(next_child.isInvalid() or self.isValid(next_child));

    for (children) |child_handle| {
        std.debug.assert(self.isValid(child_handle));

        const child = self.getMut(child_handle);
        std.debug.assert(child.parent.isInvalid());

        child.prev_sibling = prev_child;
        prev_child = child_handle;
    }

    const last_child_handle = children[children.len - 1];
    const last_child = self.getMut(last_child_handle);
    last_child.next_sibling = next_child;

    if (parent.first_child.isInvalid()) {
        std.debug.assert(parent.last_child.isInvalid());

        parent.first_child = children[0];
        parent.last_child = last_child_handle;
    }
}

pub fn addChildren(self: *Tree, parent_handle: Element.Handle, children: []const Element.Handle) void {
    std.debug.assert(self.isValid(parent_handle));
    if (children.len == 0) return;

    const parent = self.getMut(parent_handle);
    var cur_child_handle = parent.last_child;

    for (children) |child_handle| {
        std.debug.assert(self.isValid(child_handle));

        const child = self.getMut(child_handle);
        std.debug.assert(child.parent.isInvalid());
        child.parent = parent_handle;

        if (cur_child_handle.isInvalid()) {
            parent.first_child = child_handle;
        } else {
            const last_child = self.getMut(parent.last_child);
            std.debug.assert(last_child.next_sibling.isInvalid());

            last_child.next_sibling = child_handle;
            child.prev_sibling = parent.last_child;
        }
        parent.last_child = child_handle;

        cur_child_handle = child_handle;
    }
}

pub fn removeChild(self: *Tree, child_handle: Element.Handle) void {
    const child = self.getMut(child_handle);
    if (child.parent.isInvalid()) return;

    const parent = self.getMut(child.parent);
    if (parent.first_child.eql(child_handle)) {
        if (!child.next_sibling.isInvalid()) {
            std.debug.assert(self.isValid(child.next_sibling));

            parent.first_child = child.next_sibling;
        } else {
            std.debug.assert(parent.last_child.eql(child_handle));

            parent.first_child = .invalid;
            parent.last_child = .invalid;
        }
    } else if (parent.last_child.eql(child_handle)) {
        std.debug.assert(self.isValid(child.prev_sibling));

        parent.last_child = child.prev_sibling;
    }

    if (!child.next_sibling.isInvalid()) {
        const next_sibling = self.getMut(child.next_sibling);
        std.debug.assert(next_sibling.prev_sibling.eql(child_handle));

        if (!child.prev_sibling.isInvalid()) {
            const prev_sibling = self.getMut(child.prev_sibling);
            std.debug.assert(prev_sibling.next_sibling.eql(child_handle));

            next_sibling.prev_sibling = child.prev_sibling;
            prev_sibling.next_sibling = child.next_sibling;
        } else {
            next_sibling.prev_sibling = .invalid;
        }
    } else if (!child.prev_sibling.isInvalid()) {
        const prev_sibiling = self.getMut(child.prev_sibling);
        std.debug.assert(prev_sibiling.next_sibling.eql(child_handle));

        prev_sibiling.next_sibling = .invalid;
    }

    child.parent = .invalid;
}

/// The childrens should not be changed while iterating over them.
pub fn childs(self: *const Tree, parent_handle: Element.Handle) ChildIterator {
    return ChildIterator.init(self, parent_handle);
}

pub const ChildIterator = struct {
    tree: *const Tree,
    parent_handle: Element.Handle,

    next_child: Element.Handle,

    pub fn init(tree: *const Tree, parent_handle: Element.Handle) ChildIterator {
        return ChildIterator{
            .tree = tree,
            .parent_handle = parent_handle,
            .next_child = tree.get(parent_handle).first_child,
        };
    }

    pub fn peek(self: *const ChildIterator) ?Element.Handle {
        return if (self.next_child.isInvalid()) return null else self.next_child;
    }

    pub fn toss(self: *ChildIterator) void {
        self.next_child = self.tree.get(self.next_child).next_sibling;
    }

    pub fn count(self: *const ChildIterator) void {
        var len: usize = 0;
        var cur_child = self.tree.get(self.parent_handle).first_child;
        while (!cur_child.isInvalid()) {
            len += 1;
            cur_child = self.tree.get(cur_child).next_sibling;
        }
        return len;
    }
};

pub fn countChilds(self: *const Tree, handle: Element.Handle) usize {
    std.debug.assert(self.isValid(handle));
    const element = self.get(handle);

    var count: usize = 0;
    var cur_child_handle = element.first_child;
    while (!cur_child_handle.isInvalid()) : (count += 1) {
        cur_child_handle = self.get(cur_child_handle).next_sibling;
    }

    return count;
}

pub fn markDirty(self: *Tree, handle: Element.Handle) void {
    if (!self.isValid(handle)) return;

    const element = self.getMut(handle);
    element.isDirty = true;
    if (element.parent.eql(.invalid)) {
        return;
    }

    var cur_parent_element_handle: Element.Handle = element.parent;
    while (!cur_parent_element_handle.isInvalid()) {
        const parent_element = self.getMut(cur_parent_element_handle);
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

pub fn writeDebugElementTree(self: *const Tree, writer: *std.Io.Writer, handle: Element.Handle, ident: ?u16) std.Io.Writer.Error!void {
    var buf: [256]u8 = undefined;
    var fixed_allocator = std.heap.FixedBufferAllocator.init(&buf);

    return self.writeDebugTreeElementInternal(&fixed_allocator, writer, handle, ident orelse 0);
}

fn writeDebugTreeElementInternal(self: *const Tree, fixed_allocator: *std.heap.FixedBufferAllocator, writer: *std.Io.Writer, handle: Element.Handle, ident: u16) std.Io.Writer.Error!void {
    std.debug.assert(self.isValid(handle));
    const allocator = fixed_allocator.allocator();

    var child_iter = self.childs(handle);
    while (child_iter.peek()) |child_handle| : (child_iter.toss()) {
        const child = self.get(child_handle);

        // there has to be a better way
        for (0..ident) |_| {
            try writer.writeAll("    ");
        }

        const child_id = child.interface.getDebugId(&Element.GetDebugIdContext{
            .allocator = allocator,
            .tree = self,

            .handle = child_handle,
        }) catch return error.WriteFailed;
        try writer.writeAll(child_id);
        try writer.writeByte('\n');
        fixed_allocator.reset();

        try self.writeDebugTreeElementInternal(fixed_allocator, writer, child_handle, ident + 1);
    }
}
