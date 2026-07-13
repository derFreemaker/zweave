const std = @import("std");
const builtin = @import("builtin");

const Indexes = @import("index.zig");

const buildingSafe = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;

/// `0` is used for representing an invalid handle.
/// It's recomended to allocate a stub for the invalid handle.
pub fn HandleStoreT(comptime ParentT: type, comptime T: type) type {
    if (@typeInfo(T) != .int) @compileError("expected T of type 'int' found: " ++ @typeName(T));
    if (@typeInfo(T).int.signedness != .unsigned) @compileError("expected T to be 'unsigned' found: " ++ @typeName(T));

    return struct {
        pub const Handle = HandleT(ParentT, T);

        const Self = @This();

        free_handles: std.ArrayList(T),
        handles: if (buildingSafe) std.ArrayList(T) else T,

        pub fn init(allocator: std.mem.Allocator, capacity: T) std.mem.Allocator.Error!Self {
            var free_handles = try std.ArrayList(T).initCapacity(allocator, capacity);
            errdefer free_handles.deinit(allocator);

            // we start at '1' since 0 would be the invalid handle
            var handles = if (comptime buildingSafe) try std.ArrayList(T).initCapacity(allocator, free_handles.capacity) else @as(T, 1);
            errdefer if (comptime buildingSafe) handles.deinit(allocator);

            // stub for invalid handle with index: 0
            comptime std.debug.assert(Handle.invalid.index.value() == 0);
            if (comptime buildingSafe) {
                _ = try handles.append(allocator, 0);

                // sync capacity if it was initalized with zero capacity
                _ = try free_handles.ensureTotalCapacityPrecise(allocator, handles.capacity);
            }

            return Self{
                .free_handles = free_handles,
                .handles = handles,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.free_handles.deinit(allocator);

            if (comptime buildingSafe) {
                self.handles.deinit(allocator);
            }
        }

        pub fn clear(self: *Self) void {
            self.free_handles.clearRetainingCapacity();

            if (comptime buildingSafe) {
                self.handles.clearRetainingCapacity();
            }
        }

        pub fn isValid(self: *const Self, handle: Handle) bool {
            if (handle.isInvalid()) {
                return false;
            }

            if (comptime buildingSafe) {
                return self.handles.items.len > handle.index.value() and
                    self.handles.items[handle.index.value()] == handle.generation;
            } else {
                return self.handles > handle.index.value();
            }
        }

        pub fn create(self: *Self, allocator: std.mem.Allocator) std.mem.Allocator.Error!Handle {
            if (self.free_handles.pop()) |handle_index| {
                return Handle{
                    .index = .from(handle_index),
                    .generation = if (comptime buildingSafe) self.handles.items[handle_index] else void{},
                };
            }

            if (comptime buildingSafe) {
                const gen = try self.handles.addOne(allocator);
                try self.free_handles.ensureTotalCapacityPrecise(allocator, self.handles.capacity);
                gen.* = 0;

                return Handle{
                    .index = .from(@intCast(self.handles.items.len - 1)),
                    .generation = 0,
                };
            } else {
                const idx: Handle.UnderlyingT = self.handles;
                try self.free_handles.ensureTotalCapacityPrecise(allocator, idx);
                self.handles +|= 1;

                return Handle{
                    .index = .from(idx),
                    .generation = void{},
                };
            }
        }

        pub fn destroy(self: *Self, handle: Handle) void {
            if (!self.isValid(handle)) {
                return;
            }

            if (comptime buildingSafe) {
                self.handles.items[handle.index.value()] += 1;
            }

            self.free_handles.appendAssumeCapacity(handle.index.value());
        }
    };
}

/// '0' is used for representing an invalid handle.
pub fn HandleT(comptime ParentT: type, comptime T: type) type {
    if (@typeInfo(T) != .int) @compileError("expected T of type 'int' found: " ++ @typeName(T));
    if (@typeInfo(T).int.signedness != .unsigned) @compileError("expected T to be 'unsigned' found: " ++ @typeName(T));

    return packed struct {
        pub const UnderlyingT = T;

        const Self = @This();

        pub const invalid = Self{
            .index = .invalid,
            .generation = if (buildingSafe) 0 else void{},
        };

        pub inline fn isInvalid(self: Self) bool {
            return self.index.isInvalid();
        }

        pub inline fn maybeValid(self: Self) ?Self {
            return if (self.isInvalid()) null else self;
        }

        index: Indexes.IndexT(ParentT, T),
        generation: if (buildingSafe) T else void,

        pub inline fn eql(self: Self, other: Self) bool {
            if (comptime buildingSafe) {
                return self.index == other.index and
                    self.generation == other.generation;
            } else {
                return self.index == other.index;
            }
        }

        pub fn format(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            if (self.isInvalid()) {
                return writer.writeAll("invalid");
            }

            if (comptime buildingSafe) {
                return writer.print("{f}~{d}", .{ self.index, self.generation });
            } else {
                return writer.print("{f}", .{self.index});
            }
        }
    };
}
