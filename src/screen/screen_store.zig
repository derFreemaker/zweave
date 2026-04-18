const std = @import("std");

const Handles = @import("../common/handles.zig");
const Style = @import("styling.zig").Style;
const Segment = @import("segment.zig");

const ScreenStore = @This();

const StrStore = Handles.HandleStoreT([]const u8, u32);
pub const StrHandle = StrStore.Handle;

const StyleStore = Handles.HandleStoreT(Style, u32);
pub const StyleHandle = StyleStore.Handle;

const SegmentStore = Handles.HandleStoreT(Segment, u32);
pub const SegmentHandle = SegmentStore.Handle;

allocator: std.mem.Allocator,

str_store: StrStore,
strs: std.ArrayList([]const u8),

style_store: StyleStore,
styles: std.ArrayList(Style),

segment_store: SegmentStore,
segments: std.ArrayList(Segment),

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!ScreenStore {
    var str_store = try StrStore.init(allocator, 256);
    errdefer str_store.deinit(allocator);
    var strs = try std.ArrayList([]const u8).initCapacity(allocator, 256);
    errdefer strs.deinit(allocator);

    var style_store = try StyleStore.init(allocator, 256);
    errdefer style_store.deinit(allocator);
    var styles = try std.ArrayList(Style).initCapacity(allocator, 256);
    errdefer styles.deinit(allocator);

    var segment_store = try SegmentStore.init(allocator, 256);
    errdefer segment_store.deinit(allocator);
    var segments = try std.ArrayList(Segment).initCapacity(allocator, 256);
    errdefer segments.deinit(allocator);

    return ScreenStore{
        .allocator = allocator,

        .str_store = str_store,
        .strs = strs,

        .style_store = style_store,
        .styles = styles,

        .segment_store = segment_store,
        .segments = segments,
    };
}

pub fn deinit(self: *ScreenStore) void {
    self.str_store.deinit(self.allocator);
    self.strs.deinit(self.allocator);

    self.style_store.deinit(self.allocator);
    self.styles.deinit(self.allocator);

    self.segment_store.deinit(self.allocator);
    self.segments.deinit(self.allocator);
}

/// Asserts that there is no '\n' or '\r' in the provided string content.
pub fn addStr(self: *ScreenStore, str_content: []const u8) std.mem.Allocator.Error!StrHandle {
    std.debug.assert(std.mem.findAny(u8, str_content, "\n\r") == null);

    const handle = try self.str_store.create(self.allocator);
    if (handle.index.value() > self.strs.capacity) {
        try self.strs.ensureTotalCapacity(self.allocator, self.strs.capacity + 1);
    }

    const str: *[]const u8 = &self.strs.allocatedSlice()[handle.index.value()];
    str.* = str_content;

    return handle;
}

pub fn removeStr(self: *ScreenStore, handle: StrHandle) void {
    self.str_store.destroy(handle);
}

pub fn getStr(self: *const ScreenStore, handle: StrHandle) []const u8 {
    std.debug.assert(self.str_store.isValid(handle));
    return self.strs.allocatedSlice()[handle.index.value()];
}

pub fn addStyle(self: *ScreenStore, style: Style) std.mem.Allocator.Error!StyleHandle {
    const handle = try self.style_store.create(self.allocator);
    if (handle.index.value() > self.styles.capacity) {
        try self.styles.ensureTotalCapacity(self.allocator, self.styles.capacity + 1);
    }

    const style_ptr: *Style = &self.styles.allocatedSlice()[handle.index.value()];
    style_ptr.* = style;

    return handle;
}

pub fn removeStyle(self: *ScreenStore, handle: StyleHandle) void {
    self.style_store.destroy(handle);
}

pub fn getStyle(self: *const ScreenStore, handle: StyleHandle) *const Style {
    std.debug.assert(self.style_store.isValid(handle));
    return &self.styles.allocatedSlice()[handle.index.value()];
}

pub fn addSegment(self: *ScreenStore, segment: Segment) std.mem.Allocator.Error!SegmentHandle {
    const handle = try self.segment_store.create(self.allocator);
    if (handle.index.value() > self.segments.capacity) {
        try self.styles.ensureTotalCapacity(self.allocator, self.segments.capacity + 1);
    }

    const segment_ptr: *Segment = &self.segments.allocatedSlice()[handle.index.value()];
    segment_ptr.* = segment;

    return handle;
}

pub fn removeSegment(self: *ScreenStore, handle: SegmentHandle) void {
    self.segment_store.destroy(handle);
}

pub fn getSegment(self: *const ScreenStore, handle: SegmentHandle) *const Segment {
    std.debug.assert(self.segment_store.isValid(handle));
    return &self.segments.allocatedSlice()[handle.index.value()];
}
