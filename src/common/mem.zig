const std = @import("std");
const builtin = @import("builtin");

/// Zero a buffer using AVX2 non-temporal (streaming) stores.
/// Bypasses cache (no RFO), writing straight to DRAM.
///
/// Requirements:
///   - `ptr` must be 32-byte aligned (required by vmovntdq)
///   - `len` must be a multiple of 32 (one YMM register width)
fn zeroAvx2NonTemporal(ptr: [*]align(32) u8, len: usize) void {
    std.debug.assert(len % 32 == 0);
    if (comptime !builtin.cpu.has(.x86, .avx2)) {
        @compileError("zeroAvx2NonTemporal: requires x86 architecture and avx2 cpu feature");
    }

    var i: usize = 0;
    while (i < len) : (i += 32) {
        asm volatile (
            \\ vmovntdq %[zero], (%[dst])
            :
            : [dst] "r" (ptr + i),
              [zero] "x" (@as(@Vector(32, u8), @splat(0))),
        );
    }

    // Required after a run of non-temporal stores: ensures the writes
    // are globally visible before any subsequent read/DMA/other-core
    // access.
    asm volatile ("sfence" ::: .{});
}

pub fn zeroBuffer(buf: []u8) void {
    const addr = @intFromPtr(buf.ptr);
    const align_offset = (32 - (addr % 32)) % 32;

    const head_len = @min(align_offset, buf.len);
    if (head_len > 0) @memset(buf[0..head_len], 0);

    const aligned_start = buf.ptr + head_len;
    const remaining = buf.len - head_len;
    const nt_len = remaining - (remaining % 32);

    if (nt_len > 0) {
        const aligned_ptr: [*]align(32) u8 = @alignCast(aligned_start);
        zeroAvx2NonTemporal(aligned_ptr, nt_len);
    }

    const tail_start = head_len + nt_len;
    if (tail_start < buf.len) @memset(buf[tail_start..], 0);
}

test "zeroBuffer correctness" {
    const buf = try std.testing.allocator.alloc(u8, 1024 * 1024);
    defer std.testing.allocator.free(buf);

    @memset(buf, 0xAA); // dirty it first
    zeroBuffer(buf);

    for (buf) |b| try std.testing.expect(b == 0);
}
