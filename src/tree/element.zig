const std = @import("std");
const zttio = @import("zttio");

const ScreenVec = @import("../common/screen_vec.zig");
const Unicode = @import("../common/unicode.zig");
const Handles = @import("../common/handles.zig");
const LayoutData = @import("../layout/layout_data.zig");
const Tree = @import("tree.zig");
const ScreenView = @import("../screen/view.zig");
const ScreenStore = @import("../screen/screen_store.zig");
const Event = @import("../event.zig").Event;

pub const HandleStore = Handles.HandleStoreT(Element, u16);
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

        onEvent: ?*const fn (self_ctx: SelfContext, ctx: *OnEventContext) OnEventError!void = passEventToChildren,
    };

    ptr: *anyopaque,
    vtable: *const VTable,

    handle: Element.Handle = .invalid,

    var dummy_: u8 = 0;
    pub const dummy = Interface{
        .ptr = &dummy_,
        .vtable = &VTable{
            .computeLayout = struct {
                pub fn func(self_ctx: SelfContext, ctx: *const ComputeLayoutContext) ComputeLayoutError!ScreenVec {
                    _ = self_ctx;
                    _ = ctx;

                    return .zero;
                }
            }.func,

            .draw = struct {
                pub fn func(self_ctx: SelfContext, ctx: *const DrawContext) DrawError!void {
                    _ = self_ctx;
                    _ = ctx;

                    return;
                }
            }.func,
        },
    };

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

    pub fn onEvent(self: Interface, ctx: *OnEventContext) OnEventError!void {
        if (self.vtable.onEvent) |func| {
            return func(self.context(), ctx);
        }
    }
};

pub fn passEventToChildren(self_ctx: SelfContext, ctx: *OnEventContext) OnEventError!void {
    var child_iter = ctx.tree.childs(self_ctx.handle);
    while (child_iter.peek()) |child_handle| : (child_iter.toss()) {
        if (ctx.consumed) break;
        const child = ctx.tree.get(child_handle);

        try child.interface.onEvent(ctx);
    }
}

pub const SelfContext = struct {
    ptr: *anyopaque,
    handle: Element.Handle,

    pub inline fn get(self: *const SelfContext, comptime T: type) *T {
        return @ptrCast(@alignCast(self.ptr));
    }
};

pub const GetDebugStrError = std.mem.Allocator.Error;

pub const GetDebugStrContext = struct {
    const Context = @This();

    allocator: std.mem.Allocator,
    tree: *const Tree,

    pub inline fn getElement(self: *const Context) *const Element {
        return self.tree.get(self.handle);
    }
};

pub const RegisterError = std.mem.Allocator.Error;

pub const RegisterContext = struct {
    const Context = @This();

    tree: *Tree,
};

pub const UnregisterContext = struct {
    const Context = @This();

    tree: *Tree,
};

pub const ComputeLayoutError = std.mem.Allocator.Error;

pub const ComputeLayoutContext = struct {
    const Context = @This();

    allocator: std.mem.Allocator,
    tree: *Tree,

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

    pub inline fn strWidth(self: *const Context, str: []const u8) usize {
        return self.view.strWidth(str);
    }

    pub inline fn isFocused(self: *const Context, handle: Element.Handle) bool {
        return self.tree.isFocused(handle);
    }

    pub inline fn child(self: *const DrawContext, view: ScreenView) DrawContext {
        return DrawContext{
            .tree = self.tree,

            .view = view,
            .screen_store = self.screen_store,
        };
    }
};

pub const OnEventError = std.mem.Allocator.Error;

pub const OnEventContext = struct {
    const Context = @This();

    tree: *Tree,

    event: *const Event,
    consumed: bool = false,

    pub inline fn consume(self: *Context) void {
        self.consumed = true;
    }
};
