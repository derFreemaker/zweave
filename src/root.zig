pub const Engine = @import("engine.zig");

pub const Tree = @import("tree/tree.zig");
pub const Element = @import("tree/element.zig");
pub const LayoutConstraints = @import("tree/layout_constraints.zig");

pub const ScreenVec = @import("common/screen_vec.zig");
pub const Screen = @import("screen/screen.zig");
pub const Style = @import("screen/styling.zig").Style;
pub const ScreenStore = @import("screen/screen_store.zig");
pub const StrHandle = ScreenStore.StrHandle;
pub const StyleHandle = ScreenStore.StyleHandle;
pub const SegmentHandle = ScreenStore.SegmentHandle;

pub const Components = struct {
    pub const Container = @import("components/container.zig");
    pub const Screen = @import("components/screen.zig");
    pub const TextInput = @import("components/text_input.zig");
};

test {
    const std = @import("std");
    std.testing.refAllDeclsRecursive(@This());
}
