const std = @import("std");

pub fn sum(comptime T: type, slice: []const T) T {
    var i: usize = 0;
    var total: T = 0;

    if (std.simd.suggestVectorLength(T)) |vec_len| {
        const Vec = @Vector(vec_len, T);
        var acc: Vec = @splat(0);
        while (i + vec_len <= slice.len) : (i += vec_len) {
            const chunk: Vec = slice[i..][0..vec_len].*;
            acc += chunk;
        }

        total = @reduce(.Add, acc);
    }

    while (i < slice.len) : (i += 1) {
        total += slice[i];
    }

    return total;
}
