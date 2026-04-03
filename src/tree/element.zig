const std = @import("std");
const zttio = @import("zttio");

const ScreenVec = @import("../common/screen_vec.zig");
const Unicode = @import("../common/unicode.zig");
const Handles = @import("../common/handles.zig");
const LayoutData = @import("../layout/layout_data.zig");
const LayoutConstraints = @import("../layout/layout_constraints.zig");
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

isDirty: bool = true,
childIsDirty: bool = false,

pub const Interface = struct {
    pub const VTable = struct {
        getDebugId: *const fn (self_ctx: SelfContext, ctx: *const GetDebugIdContext) GetDebugIdError![]const u8 = getElementIndexAsDebugId,
        register: ?*const fn (self_ctx: SelfContext, ctx: *const RegisterContext) RegisterError!void = null,

        getLayoutConstraints: *const fn (self_ctx: SelfContext, ctx: *const GetLayoutConstraintsContext) GetLayoutConstraintsError!LayoutConstraints,
        computeLayout: ?*const fn (self_ctx: SelfContext, ctx: *const CalcLayoutContext) CalcLayoutError!ScreenVec = null,
        draw: *const fn (self_ctx: SelfContext, ctx: *const DrawContext) DrawError!void,

        onEvent: ?*const fn (self_ctx: SelfContext, ctx: *OnEventContext) OnEventError!void = null,
    };

    ptr: *anyopaque,
    vtable: *const VTable,

    handle: Element.Handle = .invalid,

    var dummy_: u8 = 0;
    pub const dummy = Interface{
        .ptr = &dummy_,
        .vtable = &VTable{
            .getLayoutConstraints = struct {
                pub fn func(self_ctx: SelfContext, ctx: *const GetLayoutConstraintsContext) GetLayoutConstraintsError!LayoutConstraints {
                    _ = self_ctx;
                    _ = ctx;

                    return LayoutConstraints{
                        .height = .{ .fixed = 0 },
                        .width = .{ .fixed = 0 },
                    };
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

    pub inline fn getDebugId(self: Interface, ctx: *const GetDebugIdContext) GetDebugIdError![]const u8 {
        return self.vtable.getDebugId(self.context(), ctx);
    }

    pub inline fn hasRegister(self: Interface) bool {
        return self.vtable.register != null;
    }

    pub inline fn register(self: Interface, ctx: *const RegisterContext) RegisterError!void {
        if (self.vtable.register) |register_func| {
            return register_func(self.context(), ctx);
        }
    }

    pub inline fn getLayoutConstraints(self: Interface, ctx: *const GetLayoutConstraintsContext) GetLayoutConstraintsError!LayoutConstraints {
        return self.vtable.getLayoutConstraints(self.context(), ctx);
    }

    pub inline fn hasComputeLayout(self: Interface) bool {
        return self.vtable.computeLayout != null;
    }

    pub inline fn computeLayout(self: Interface, ctx: *const CalcLayoutContext) CalcLayoutError!ScreenVec {
        if (self.vtable.computeLayout) |func| {
            return func(self.context(), ctx);
        }

        return ctx.available;
    }

    pub inline fn draw(self: Interface, ctx: *const DrawContext) DrawError!void {
        return self.vtable.draw(self.context(), ctx);
    }

    pub inline fn hasOnEvent(self: Interface) bool {
        return self.vtable.onEvent != null;
    }

    pub inline fn onEvent(self: Interface, ctx: *OnEventContext) OnEventError!void {
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

pub const GetDebugIdError = std.mem.Allocator.Error;

pub const GetDebugIdContext = struct {
    const Context = @This();

    allocator: std.mem.Allocator,
    tree: *const Tree,

    pub inline fn getElement(self: *const Context) *const Element {
        return self.tree.get(self.handle);
    }
};

fn getElementIndexAsDebugId(self_ctx: SelfContext, ctx: *const GetDebugIdContext) GetDebugIdError![]const u8 {
    _ = self_ctx;
    _ = ctx;

    return "<{Element}>";
}

pub const RegisterError = std.mem.Allocator.Error;

pub const RegisterContext = struct {
    const Context = @This();

    tree: *Tree,
};

pub const GetLayoutConstraintsError = std.mem.Allocator.Error;

pub const GetLayoutConstraintsContext = struct {
    const Context = @This();

    allocator: std.mem.Allocator,
    tree: *const Tree,

    width_method: Unicode.WidthMethod,

    pub inline fn strWidth(self: *const Context, str: []const u8) usize {
        return Unicode.strWidth(str, self.width_method);
    }
};

pub const CalcLayoutError = std.mem.Allocator.Error;

pub const CalcLayoutContext = struct {
    const Context = @This();

    allocator: std.mem.Allocator,
    tree: *Tree,

    viewport_size: ScreenVec,
    width_method: Unicode.WidthMethod,
    available: ScreenVec,

    pub inline fn strWidth(self: *const Context, str: []const u8) usize {
        return Unicode.strWidth(str, self.width_method);
    }

    pub inline fn toGetLayoutConstraintsContext(self: *const Context) GetLayoutConstraintsContext {
        return GetLayoutConstraintsContext{
            .allocator = self.allocator,
            .tree = self.tree,

            .width_method = self.width_method,
        };
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
