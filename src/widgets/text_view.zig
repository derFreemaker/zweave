const std = @import("std");

const GraphemeGapBuffer = @import("../common/grapheme_gap_buffer.zig");
const ScrollView = @import("../components/scroll_view.zig");
const ScreenVec = @import("../screen/screen_vec.zig");

const TextView = @This();

allocator: std.mem.Allocator,
buf: GraphemeGapBuffer,
scroll_view: ScrollView,

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!TextView {
    return TextView{
        .allocator = allocator,
        .buf = try GraphemeGapBuffer.initCapacity(allocator, 256),
        .scroll_view = .{},
    };
}

pub fn deinit(self: *TextView) void {
    _ = self; // autofix
}
