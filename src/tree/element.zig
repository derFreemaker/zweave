const std = @import("std");

const Unicode = @import("../common/unicode.zig");
const Handles = @import("../handles.zig");
const LayoutConstraints = @import("layout_constraints.zig");
const Tree = @import("tree.zig");
const Screen = @import("../screen/screen.zig");
const ScreenStore = @import("../screen/screen_store.zig");

pub const HandleStore = Handles.HandleStoreT(Element, u16, .buildSafety);
pub const Handle = HandleStore.Handle;

const Element = @This();

pub const Interface = struct {
    pub const VTable = struct {
        // registerInLayout: ?*const fn (self_ptr: *anyopaque, tree: *Tree) std.mem.Allocator.Error!void = null,
        getLayoutConstraints: *const fn (ctx: *const GetLayoutConstraintsContext) GetLayoutConstraintsError!LayoutConstraints,
        computeLayout: ?*const fn (ctx: *const CalcLayoutContext) CalcLayoutError!SmallVec2 = null,
        draw: *const fn (ctx: *const DrawContext) DrawError!void,
    };

    ptr: *anyopaque,
    vtable: *const VTable,
};

parent: Handle = .invalid,
interface: Interface,

//TODO: move children into a map for faster modification
children: std.ArrayList(Handle) = .empty,

isDirty: bool = true,
childIsDirty: bool = false,

pub const GetLayoutConstraintsError = std.mem.Allocator.Error;

pub const GetLayoutConstraintsContext = struct {
    allocator: std.mem.Allocator,
    tree: *const Tree,
    width_method: Unicode.WidthMethod,

    self: *const Element,
    self_handle: Element.Handle,

    pub inline fn strWidth(self: *const GetLayoutConstraintsContext, str: []const u8) usize {
        return Unicode.strWidth(str, self.width_method);
    }

    pub fn getSelf(self: *const GetLayoutConstraintsContext, comptime T: type) *T {
        return @ptrCast(@alignCast(self.self.interface.ptr));
    }
};

pub const CalcLayoutError = DrawError || std.mem.Allocator.Error;

pub const CalcLayoutContext = struct {
    allocator: std.mem.Allocator,
    tree: *Tree,
    width_method: Unicode.WidthMethod,

    self: *const Element,
    self_handle: Element.Handle,

    available: SmallVec2,

    pub inline fn strWidth(self: *const CalcLayoutContext, str: []const u8) usize {
        return Unicode.strWidth(str, self.width_method);
    }

    pub fn getSelf(self: *const CalcLayoutContext, comptime T: type) *T {
        return @ptrCast(@alignCast(self.self.interface.ptr));
    }
};

//TODO: move style and segment registration outside of draw function to avoid memory allocation in draw
pub const DrawError = std.mem.Allocator.Error;

pub const DrawContext = struct {
    tree: *const Tree,

    self: *const Element,
    self_handle: Element.Handle,

    view: Screen.View,
    screen_store: *const ScreenStore,

    pub inline fn strWidth(self: *const DrawContext, str: []const u8) usize {
        return self.view.strWidth(str);
    }

    pub fn getSelf(self: *const DrawContext, comptime T: type) *T {
        return @ptrCast(@alignCast(self.self.interface.ptr));
    }
};

pub const SmallVec2 = struct {
    x: u16,
    y: u16,
};
