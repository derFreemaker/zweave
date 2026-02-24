const std = @import("std");
const builtin = @import("builtin");

const buildingSafe = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;

pub fn HandleStoreT(comptime ParentT: type, comptime T: type) type {
    return struct {
        pub const Handle = HandleT(ParentT, T);

        const Self = @This();

        free_handles: std.ArrayList(T),
        handles: if (buildingSafe) std.ArrayList(T) else usize,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) std.mem.Allocator.Error!Self {
            return Self{
                .free_handles = try .initCapacity(allocator, capacity),
                .handles = if (comptime buildingSafe) try .initCapacity(allocator, capacity) else 0,
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
            } else {
                self.handles = 0;
            }
        }

        pub fn isValid(self: *const Self, handle: Handle) bool {
            if (comptime buildingSafe) {
                return self.handles.items.len > handle.index and
                    self.handles.items[handle.index] == handle.generation;
            } else {
                return self.handles > handle.index;
            }
        }

        pub fn create(self: *Self, allocator: std.mem.Allocator) std.mem.Allocator.Error!Handle {
            if (self.free_handles.getLastOrNull()) |handle_index| {
                _ = self.free_handles.pop();

                return Handle{
                    .index = handle_index,
                    .generation = if (comptime buildingSafe) self.handles.items[handle_index] else void{},
                };
            }

            if (comptime buildingSafe) {
                const gen = try self.handles.addOne(allocator);
                try self.free_handles.ensureTotalCapacityPrecise(allocator, self.handles.capacity);
                gen.* = 0;

                return Handle{
                    .index = @intCast(self.handles.items.len - 1),
                    .generation = 0,
                };
            } else {
                const handle = Handle{
                    .index = self.handles,
                    .generation = void{},
                };
                self.handles += 1;
                try self.free_handles.ensureTotalCapacity(allocator, self.handles);

                return handle;
            }
        }

        pub fn remove(self: *Self, handle: Handle) void {
            if (!self.isValid(handle)) return;

            if (comptime buildingSafe) {
                self.handles.items[handle.index] +|= 1;
            }

            self.free_handles.appendAssumeCapacity(handle.index);
        }

        pub fn count(self: *const Self) usize {
            return if (comptime buildingSafe) self.handles.items.len else self.handles;
        }
    };
}

pub fn HandleT(comptime ParentT: type, comptime T: type) type {
    // we only need the parent type for uniques
    _ = ParentT;

    if (@typeInfo(T) != .int) @compileError("expected T of type 'int' found: " ++ @typeName(T));

    return struct {
        const Self = @This();

        pub const invalid = Self{ .index = std.math.maxInt(T), .generation = if (buildingSafe) 0 else void{} };

        index: T,
        generation: if (buildingSafe) T else void,
    };
}
