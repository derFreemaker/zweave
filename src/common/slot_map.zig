const std = @import("std");

const Handles = @import("handles.zig");

pub fn SlotMap(comptime T: type, comptime HandleSize: type) type {
    if (@typeInfo(HandleSize) != .int) @compileError("expected HandleSize of type 'int' found: " ++ @typeName(HandleSize));
    if (@typeInfo(HandleSize).int.signedness != .unsigned) @compileError("expected HandleSize to be 'unsigned' found: " ++ @typeName(HandleSize));

    return struct {
        const HandleStore = Handles.HandleStoreT(T, HandleSize);
        pub const Handle = HandleStore.Handle;

        const Self = @This();

        store: HandleStore,
        data: []T,

        pub fn init(allocator: std.mem.Allocator, capacity: HandleSize) std.mem.Allocator.Error!Self {
            var store = try HandleStore.init(allocator, capacity);
            errdefer store.deinit(allocator);

            const data = try allocator.alloc(T, capacity);
            errdefer allocator.free(data);

            // Zeroing slot for the stub which is at invalid index, which should be '0'.
            comptime std.debug.assert(Handle.invalid.index.value() == 0);
            @memset(std.mem.asBytes(&data[0]), 0);

            return Self{
                .store = store,
                .data = data,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.store.deinit(allocator);
            allocator.free(self.data);
        }

        pub fn create(self: *Self, allocator: std.mem.Allocator) std.mem.Allocator.Error!Handle {
            const handle = try self.store.create(allocator);
            try self.ensureCapacity(allocator, handle.index.value());

            return handle;
        }

        pub fn add(self: *Self, allocator: std.mem.Allocator, value: T) std.mem.Allocator.Error!Handle {
            const handle = try self.create(allocator);
            self.data[handle.index.value()] = value;
            return handle;
        }

        pub inline fn get(self: *const Self, handle: Handle) *T {
            std.debug.assert(self.store.isValid(handle));
            return &self.data[handle.index.value()];
        }

        pub inline fn destroy(self: *Self, handle: Handle) void {
            return self.store.destroy(handle);
        }

        pub fn ensureCapacity(self: *Self, allocator: std.mem.Allocator, new_capacity: usize) std.mem.Allocator.Error!void {
            if (self.data.len >= new_capacity) {
                return;
            }

            if (allocator.remap(self.data, new_capacity)) |new_memory| {
                self.data = new_memory;
            } else {
                const new_memory = try allocator.alloc(T, new_capacity);
                @memcpy(new_memory[0..self.data.len], self.data);
                allocator.free(self.data);
                self.data = new_memory;
            }
        }

        pub fn grow(minimum: usize) usize {
            return minimum +| (minimum / 2);
        }
    };
}
