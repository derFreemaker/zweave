pub const Tty = @import("tty.zig").Tty;
pub const Engine = @import("engine.zig");

pub const ScreenVec = @import("common/screen_vec.zig");
pub const Event = @import("event.zig").Event;

pub const Tree = @import("tree/tree.zig");
pub const Element = @import("tree/element.zig");

pub const Screen = @import("screen/screen.zig");
pub const Style = @import("screen/styling.zig").Style;
pub const ScreenStore = @import("screen/screen_store.zig");
pub const StrHandle = ScreenStore.StrHandle;
pub const StyleHandle = ScreenStore.StyleHandle;
pub const SegmentHandle = ScreenStore.SegmentHandle;

pub const Widgets = struct {
    pub const Container = @import("widgets/container.zig");
    pub const Screen = @import("widgets/screen.zig");
    pub const TextInput = @import("widgets/text_input.zig");
};

test {
    const std = @import("std");
    std.testing.refAllDeclsRecursive(@This());
}
