const std = @import("std");

pub fn sum(comptime T: type, slice: []const T) T {
    const vec_len = std.simd.suggestVectorLength(T) orelse return scalarSum(T, slice);
    const Vec = @Vector(vec_len, T);

    var acc: Vec = @splat(0);
    var i: usize = 0;
    while (i + vec_len <= slice.len) : (i += vec_len) {
        const chunk: Vec = slice[i..][0..vec_len].*;
        acc += chunk;
    }

    var total: T = @reduce(.Add, acc);

    while (i < slice.len) : (i += 1) {
        total += slice[i];
    }

    return total;
}

fn scalarSum(comptime T: type, slice: []const T) T {
    var total: T = 0;
    for (slice) |val| total += val;
    return total;
}
