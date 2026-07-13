const ScreenVec = @import("../screen/screen_vec.zig");

const LayoutData = @This();

pub const zero = LayoutData{
    .pos = .zero,
    .size = .zero,
};

/// relative to parent element
pos: ScreenVec,

size: ScreenVec,
