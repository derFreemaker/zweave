const std = @import("std");

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

    self: *const Element,
    self_handle: Element.Handle,
};

pub const CalcLayoutError = DrawError || std.mem.Allocator.Error;

pub const CalcLayoutContext = struct {
    allocator: std.mem.Allocator,
    tree: *Tree,

    self: *const Element,
    self_handle: Element.Handle,

    available: SmallVec2,
};

//TODO: move style and segment registration outside of draw function to avoid memory allocation in draw
pub const DrawError = std.mem.Allocator.Error;

pub const DrawContext = struct {
    tree: *const Tree,

    self: *const Element,
    self_handle: Element.Handle,

    view: Screen.View,
    screen_store: *const ScreenStore,
};

pub const SmallVec2 = struct {
    x: u16,
    y: u16,
};
