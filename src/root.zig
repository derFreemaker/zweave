pub const zttio = @import("zttio");

pub const Engine = @import("engine.zig");
pub const Event = @import("event.zig").Event;
pub const Screen = @import("screen/screen.zig");
pub const ScreenStore = @import("screen/screen_store.zig");
pub const StrHandle = ScreenStore.StrHandle;
pub const StylingHandle = ScreenStore.StylingHandle;
pub const SegmentHandle = ScreenStore.SegmentHandle;
pub const ScreenVec = @import("screen/screen_vec.zig");
pub const Styling = @import("screen/styling.zig").Styling;
pub const Element = @import("tree/element.zig");
pub const Tree = @import("tree/tree.zig");

pub const Widgets = struct {
    pub const Container = @import("widgets/container.zig");
    pub const Frame = @import("widgets/frame.zig");

    pub const Screen = @import("widgets/screen.zig");
    pub const TextInput = @import("widgets/text_input.zig");
};

pub const Symbols = struct {
    pub const BoxDrawing = @import("symbols/box_drawing.zig");
};

test {
    _ = @import("common/gap_buffer.zig");
    _ = @import("tree/tree.zig");

    const testing = @import("testing.zig");
    testing.refAllDeclsRecursive(@This());
}
