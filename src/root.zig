pub const Engine = @import("engine.zig");

pub const Screen = @import("screen/screen.zig");
pub const Style = @import("screen/styling.zig").Style;
pub const Tree = @import("tree/tree.zig");
pub const Element = @import("tree/element.zig");
pub const LayoutConstraints = @import("tree/layout_constraints.zig");

pub const ScreenStore = @import("screen/screen_store.zig");
pub const StrHandle = ScreenStore.StrHandle;
pub const StyleHandle = ScreenStore.StyleHandle;
pub const SegmentHandle = ScreenStore.SegmentHandle;

pub const Tracy = struct {
    pub const Tracy = @import("tracy");
    pub const TracyImpl = @import("tracy_impl");
};

test {
    const std = @import("std");
    std.testing.refAllDeclsRecursive(@This());
}
