const std = @import("std");

const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

const CountingAllocator = @This();

child_allocator: Allocator,
bytes_used: u64 = 0,

pub fn init(child_allocator: Allocator) CountingAllocator {
    return CountingAllocator{
        .child_allocator = child_allocator,
    };
}

pub fn allocator(self: *CountingAllocator) Allocator {
    return Allocator{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        },
    };
}

pub fn alloc(self_ptr: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
    const self: *CountingAllocator = @ptrCast(@alignCast(self_ptr));
    const memory = self.child_allocator.rawAlloc(len, alignment, ret_addr) orelse return null;

    self.bytes_used += len;

    return memory;
}

pub fn resize(self_ptr: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
    const self: *CountingAllocator = @ptrCast(@alignCast(self_ptr));
    if (!self.child_allocator.rawResize(memory, alignment, new_len, ret_addr)) {
        return false;
    }

    self.bytes_used -= memory.len;
    self.bytes_used += new_len;

    return true;
}

pub fn remap(self_ptr: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    const self: *CountingAllocator = @ptrCast(@alignCast(self_ptr));
    const remapped = self.child_allocator.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;

    self.bytes_used -= memory.len;
    self.bytes_used += new_len;

    return remapped;
}

pub fn free(self_ptr: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
    const self: *CountingAllocator = @ptrCast(@alignCast(self_ptr));
    self.child_allocator.rawFree(memory, alignment, ret_addr);

    self.bytes_used -= memory.len;
}

pub fn prettyPrintBytesUsed(self: *const CountingAllocator, str_allocator: Allocator) Allocator.Error![]u8 {
    if (self.bytes_used < 3 * 1024) {
        return std.fmt.allocPrint(str_allocator, "{d}B", .{self.bytes_used});
    } else if (self.bytes_used < 3 * 1024 * 1024) {
        return std.fmt.allocPrint(str_allocator, "{d:.1}kB", .{@as(f32, @floatFromInt(self.bytes_used)) / 1024});
    } else if (self.bytes_used < 3 * 1024 * 1024 * 1024) {
        return std.fmt.allocPrint(str_allocator, "{d:.1}MB", .{@as(f32, @floatFromInt(self.bytes_used)) / (1024 * 1024)});
    } else {
        return std.fmt.allocPrint(str_allocator, "{d:.1}GB", .{@as(f64, @floatFromInt(self.bytes_used)) / (1024 * 1024 * 1024)});
    }
}
