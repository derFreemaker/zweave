const std = @import("std");
const zttio = @import("zttio");

const ScreenVec = @import("../common/screen_vec.zig");
const Unicode = @import("../common/unicode.zig");
const Handles = @import("../common/handles.zig");
const LayoutConstraints = @import("layout_constraints.zig");
const Tree = @import("tree.zig");
const ScreenView = @import("../screen/view.zig");
const ScreenStore = @import("../screen/screen_store.zig");
const Event = @import("../event.zig").Event;

pub const HandleStore = Handles.HandleStoreT(Element, u16, .buildSafety);
pub const Handle = HandleStore.Handle;

const Element = @This();

pub const Interface = struct {
    pub const VTable = struct {
        register: ?*const fn (self_ptr: *anyopaque, ctx: *const RegisterContext) RegisterError!void = null,

        getLayoutConstraints: *const fn (self_ptr: *anyopaque, ctx: *const GetLayoutConstraintsContext) GetLayoutConstraintsError!LayoutConstraints,
        computeLayout: ?*const fn (self_ptr: *anyopaque, ctx: *const CalcLayoutContext) CalcLayoutError!ScreenVec = null,
        draw: *const fn (self_ptr: *anyopaque, ctx: *const DrawContext) DrawError!void,

        onEvent: ?*const fn (self_ptr: *anyopaque, ctx: *const EventContext) EventError!void = null,
    };

    ptr: *anyopaque,
    vtable: *const VTable,

    pub inline fn hasRegister(self: Interface) bool {
        return self.vtable.register != null;
    }

    pub inline fn register(self: Interface, ctx: *const RegisterContext) RegisterError!void {
        return self.vtable.register.?(self.ptr, ctx);
    }

    pub inline fn getLayoutConstraints(self: Interface, ctx: *const GetLayoutConstraintsContext) GetLayoutConstraintsError!LayoutConstraints {
        return self.vtable.getLayoutConstraints(self.ptr, ctx);
    }

    pub inline fn hasComputeLayout(self: Interface) bool {
        return self.vtable.computeLayout != null;
    }

    pub inline fn computeLayout(self: Interface, ctx: *const CalcLayoutContext) CalcLayoutError!ScreenVec {
        return self.vtable.computeLayout.?(self.ptr, ctx);
    }

    pub inline fn draw(self: Interface, ctx: *const DrawContext) DrawError!void {
        return self.vtable.draw(self.ptr, ctx);
    }

    pub inline fn hasOnEvent(self: Interface) bool {
        return self.vtable.onEvent != null;
    }

    pub inline fn onEvent(self: Interface, ctx: *const EventContext) EventError!void {
        if (self.vtable.onEvent == null) return;
        return self.vtable.onEvent.?(self.ptr, ctx);
    }
};

parent: Handle = .invalid,
interface: Interface,

//TODO: optimize children faster modification
children: std.ArrayList(Handle) = .empty,

isDirty: bool = true,
childIsDirty: bool = false,

pub const RegisterError = std.mem.Allocator.Error;

pub const RegisterContext = struct {
    const Context = @This();

    tree: *Tree,
    handle: Element.Handle,

    pub inline fn getElement(self: *const Context) *const Element {
        return self.tree.get(self.handle);
    }

    pub inline fn getElementMut(self: *const Context) *Element {
        return self.tree.getMut(self.handle);
    }
};

pub const GetLayoutConstraintsError = std.mem.Allocator.Error;

pub const GetLayoutConstraintsContext = struct {
    const Context = @This();

    allocator: std.mem.Allocator,
    tree: *const Tree,
    width_method: Unicode.WidthMethod,

    handle: Element.Handle,

    pub inline fn strWidth(self: *const Context, str: []const u8) usize {
        return Unicode.strWidth(str, self.width_method);
    }

    pub inline fn getElement(self: *const Context) *const Element {
        return self.tree.get(self.handle);
    }
};

pub const CalcLayoutError = std.mem.Allocator.Error;

pub const CalcLayoutContext = struct {
    const Context = @This();

    allocator: std.mem.Allocator,
    tree: *Tree,
    width_method: Unicode.WidthMethod,

    handle: Element.Handle,

    available: ScreenVec,

    pub inline fn strWidth(self: *const Context, str: []const u8) usize {
        return Unicode.strWidth(str, self.width_method);
    }

    pub inline fn getElement(self: *const Context) *const Element {
        return self.tree.get(self.handle);
    }

    pub inline fn getElementMut(self: *const Context) *Element {
        return self.tree.getMut(self.handle);
    }
};

pub const DrawError = std.Io.Writer.Error || std.mem.Allocator.Error;

pub const DrawContext = struct {
    const Context = @This();

    tree: *const Tree,

    handle: Element.Handle,

    view: ScreenView,
    screen_store: *const ScreenStore,

    pub inline fn strWidth(self: *const Context, str: []const u8) usize {
        return self.view.strWidth(str);
    }

    pub inline fn getElement(self: *const Context) *const Element {
        return self.tree.get(self.handle);
    }

    pub inline fn isFocused(self: *const Context) bool {
        return self.tree.isFocused(self.handle);
    }
};

pub const EventError = std.mem.Allocator.Error;

pub const EventContext = struct {
    const Context = @This();

    tree: *Tree,

    handle: Element.Handle,

    event: *const Event,

    pub inline fn getElement(self: *const Context) *const Element {
        return self.tree.get(self.handle);
    }

    pub inline fn getElementMut(self: *const Context) *Element {
        return self.tree.getMut(self.handle);
    }

    pub inline fn isFocused(self: *const Context) bool {
        return self.tree.isFocused(self.handle);
    }

    pub inline fn markDirty(self: *const Context) void {
        self.tree.markDirty(self.handle);
    }
};
