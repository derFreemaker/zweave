const std = @import("std");

const SlotMap = @import("../common/slot_map.zig").SlotMap;
const Segment = @import("segment.zig");
const Styling = @import("styling.zig").Styling;

const ScreenStore = @This();

const StrSlotMap = SlotMap([]const u8, u32);
pub const StrHandle = StrSlotMap.Handle;

const StylingSlotMap = SlotMap(Styling, u32);
pub const StylingHandle = StylingSlotMap.Handle;

const SegmentSlotMap = SlotMap(Segment, u32);
pub const SegmentHandle = SegmentSlotMap.Handle;

allocator: std.mem.Allocator,

strs: StrSlotMap,
styles: StylingSlotMap,
segments: SegmentSlotMap,

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!ScreenStore {
    var strs = try StrSlotMap.init(allocator, 256);
    errdefer strs.deinit(allocator);

    var styles = try StylingSlotMap.init(allocator, 256);
    errdefer styles.deinit(allocator);

    var segments = try SegmentSlotMap.init(allocator, 256);
    errdefer segments.deinit(allocator);

    return ScreenStore{
        .allocator = allocator,

        .strs = strs,

        .styles = styles,

        .segments = segments,
    };
}

pub fn deinit(self: *ScreenStore) void {
    self.strs.deinit(self.allocator);

    self.styles.deinit(self.allocator);

    self.segments.deinit(self.allocator);
}

pub fn addStr(self: *ScreenStore, str: []const u8) std.mem.Allocator.Error!StrHandle {
    return self.strs.add(self.allocator, str);
}

pub fn removeStr(self: *ScreenStore, handle: StrHandle) void {
    return self.strs.destroy(handle);
}

pub fn getStr(self: *const ScreenStore, handle: StrHandle) *[]const u8 {
    return self.strs.get(handle);
}

pub fn addStyling(self: *ScreenStore, styling: Styling) std.mem.Allocator.Error!StylingHandle {
    return self.styles.add(self.allocator, styling);
}

pub fn removeStyling(self: *ScreenStore, handle: StylingHandle) void {
    return self.styles.destroy(handle);
}

pub fn getStyling(self: *const ScreenStore, handle: StylingHandle) *Styling {
    return self.styles.get(handle);
}

pub fn addSegment(self: *ScreenStore, segment: Segment) std.mem.Allocator.Error!SegmentHandle {
    return self.segments.add(self.allocator, segment);
}

pub fn removeSegment(self: *ScreenStore, handle: SegmentHandle) void {
    return self.segments.destroy(handle);
}

pub fn getSegment(self: *const ScreenStore, handle: SegmentHandle) *Segment {
    return self.segments.get(handle);
}
