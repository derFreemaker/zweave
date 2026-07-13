const std = @import("std");
pub const GetDebugStrError = std.mem.Allocator.Error;
pub const RegisterError = std.mem.Allocator.Error;
pub const ComputeLayoutError = std.mem.Allocator.Error;
pub const OnEventError = std.mem.Allocator.Error;

const zttio = @import("zttio");

const Handles = @import("../common/handles.zig");
const Event = @import("../event.zig").Event;
const LayoutData = @import("../layout/layout_data.zig");
const ScreenStore = @import("../screen/screen_store.zig");
const ScreenVec = @import("../screen/screen_vec.zig");
const ScreenView = @import("../screen/view.zig");
const Unicode = @import("../unicode.zig");
const Tree = @import("tree.zig");

pub const HandleStore = Handles.HandleStoreT(Element, u32);
pub const Handle = HandleStore.Handle;

const Element = @This();

interface: Interface,

parent: Handle = .invalid,
first_child: Handle = .invalid,
last_child: Handle = .invalid,
prev_sibling: Handle = .invalid,
next_sibling: Handle = .invalid,

// isDirty: bool = true,
// childIsDirty: bool = false,

pub const Interface = struct {
    pub const VTable = struct {
        getDebugStr: ?*const fn (self_ctx: SelfContext, ctx: *const GetDebugStrContext) GetDebugStrError![]const u8 = null,
        register: ?*const fn (self_ctx: SelfContext, ctx: *const RegisterContext) RegisterError!void = null,
        unregister: ?*const fn (self_ctx: SelfContext, ctx: *const UnregisterContext) void = null,

        computeLayout: ?*const fn (self_ctx: SelfContext, ctx: *const ComputeLayoutContext) ComputeLayoutError!ScreenVec = null,
        draw: *const fn (self_ctx: SelfContext, ctx: *const DrawContext) DrawError!void,

        onEvent: ?*const fn (self_ctx: SelfContext, ctx: *const OnEventContext) OnEventError!void = passEventToChildren,
    };

    ptr: *anyopaque,
    vtable: *const VTable,

    handle: Element.Handle = .invalid,

    var dummy_: u8 = 0;
    pub const dummy = Interface{
        .ptr = &dummy_,
        .vtable = &VTable{
            .computeLayout = dummyComputeLayout,
            .draw = dummyDraw,
        },
    };

    fn dummyComputeLayout(self_ctx: SelfContext, ctx: *const ComputeLayoutContext) ComputeLayoutError!ScreenVec {
        _ = self_ctx;
        _ = ctx;
        return .zero;
    }

    fn dummyDraw(self_ctx: SelfContext, ctx: *const DrawContext) DrawError!void {
        _ = self_ctx;
        _ = ctx;
    }

    fn context(self: Interface) SelfContext {
        return SelfContext{
            .ptr = self.ptr,
            .handle = self.handle,
        };
    }

    pub fn getDebugStr(self: Interface, ctx: *const GetDebugStrContext) GetDebugStrError![]const u8 {
        if (self.vtable.getDebugStr) |func| {
            return func(self.context(), ctx);
        }

        return "<Element>";
    }

    pub fn register(self: Interface, ctx: *const RegisterContext) RegisterError!void {
        if (self.vtable.register) |func| {
            return func(self.context(), ctx);
        }
    }

    pub fn unregister(self: Interface, ctx: *const UnregisterContext) void {
        if (self.vtable.unregister) |func| {
            return func(self.context(), ctx);
        }
    }

    pub fn computeLayout(self: Interface, ctx: *const ComputeLayoutContext) ComputeLayoutError!ScreenVec {
        if (self.vtable.computeLayout) |func| {
            return func(self.context(), ctx);
        }

        return ctx.available;
    }

    pub fn draw(self: Interface, ctx: *const DrawContext) DrawError!void {
        return self.vtable.draw(self.context(), ctx);
    }

    pub fn onEvent(self: Interface, ctx: *const OnEventContext) OnEventError!void {
        if (self.vtable.onEvent) |func| {
            return func(self.context(), ctx);
        }
    }
};

pub const SelfContext = struct {
    ptr: *anyopaque,
    handle: Element.Handle,

    pub inline fn get(self: *const SelfContext, comptime T: type) *T {
        return @ptrCast(@alignCast(self.ptr));
    }
};

pub const GetDebugStrContext = struct {
    const Context = @This();

    allocator: std.mem.Allocator,
    tree: *const Tree,

    pub inline fn getElement(self: *const Context) *const Element {
        return self.tree.get(self.handle);
    }
};

pub const RegisterContext = struct {
    const Context = @This();

    tree: *Tree,
};

pub const UnregisterContext = struct {
    const Context = @This();

    tree: *Tree,
};

pub const ComputeLayoutContext = struct {
    const Context = @This();

    allocator: std.mem.Allocator,
    tree: *Tree,
    screen_store: *const ScreenStore,

    width_method: Unicode.WidthMethod,

    viewport_size: ScreenVec,
    parent_size: ScreenVec,
    available: ScreenVec,

    pub inline fn strWidth(self: *const Context, str: []const u8) usize {
        return Unicode.strWidth(str, self.width_method);
    }

    pub fn child(self: *const Context, child_size: ScreenVec) Context {
        var copy: Context = self.*;
        copy.parent_size = self.available;
        copy.available = child_size;

        return copy;
    }
};

pub const DrawError = std.Io.Writer.Error || std.mem.Allocator.Error;

pub const DrawContext = struct {
    const Context = @This();

    tree: *const Tree,

    view: ScreenView,
    screen_store: *const ScreenStore,

    mouse_rel_pos: ?ScreenVec,

    pub inline fn strWidth(self: *const Context, str: []const u8) usize {
        return self.view.strWidth(str);
    }

    pub inline fn isFocused(self: *const Context, handle: Element.Handle) bool {
        return self.tree.isFocused(handle);
    }

    pub inline fn isHovered(self: *const Context) bool {
        return self.mouse_rel_pos != null;
    }

    pub inline fn child(self: *const Context, view: ScreenView, rel_pos: ?ScreenVec) Context {
        return Context{
            .tree = self.tree,

            .view = view,
            .screen_store = self.screen_store,

            .mouse_rel_pos = rel_pos,
        };
    }
};

pub const OnEventContext = struct {
    const Context = @This();

    tree: *Tree,

    event: *const Event,
    consumed: ?*bool,

    mouse_rel_pos: ?ScreenVec,

    pub inline fn isConsumed(self: *const Context) bool {
        return if (self.consumed) |state| state.* else false;
    }

    pub inline fn consume(self: *const Context) void {
        if (self.consumed) |state| {
            state.* = true;
        }
    }

    pub inline fn isHovered(self: *const Context) bool {
        return self.mouse_rel_pos != null;
    }

    pub inline fn child(self: *const Context, rel_pos: ?ScreenVec) Context {
        return Context{
            .tree = self.tree,

            .event = self.event,
            .consumed = self.consumed,

            .mouse_rel_pos = rel_pos,
        };
    }
};

pub fn passEventToChildren(self_ctx: SelfContext, ctx: *const OnEventContext) OnEventError!void {
    var child_iter = ctx.tree.childs(self_ctx.handle);
    while (child_iter.peek()) |child_handle| : (child_iter.toss()) {
        const child = ctx.tree.get(child_handle);

        var rel_pos: ?ScreenVec = null;
        if (ctx.mouse_rel_pos) |cur_rel_pos| {
            const child_data = ctx.tree.getLayoutData(child_handle);
            rel_pos = cur_rel_pos.subOverflow(child_data.pos) catch null;
            if (rel_pos) |pos| {
                if (pos.x >= child_data.size.x or pos.y >= child_data.size.y) {
                    rel_pos = null;
                }
            }
        }

        const child_ctx = ctx.child(rel_pos);
        try child.interface.onEvent(&child_ctx);

        if (ctx.isConsumed()) break;
    }
}
