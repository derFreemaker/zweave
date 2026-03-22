const std = @import("std");
const uucode = @import("uucode");
const zttio = @import("zttio");
const tracy = @import("tracy");

pub const GraphemeClusterIterator = struct {
    str: []const u8,
    inner: uucode.grapheme.Iterator(uucode.utf8.Iterator),
    start: usize = 0,
    prev_break: bool = true,

    pub fn init(str: []const u8) GraphemeClusterIterator {
        return .{
            .str = str,
            .inner = uucode.grapheme.Iterator(uucode.utf8.Iterator).init(.init(str)),
        };
    }

    pub fn next(self: *GraphemeClusterIterator) ?GraphemeCluster {
        // const trace_zone = tracy.Zone.begin(.{
        //     .name = "[Unicode]: GraphemeClusterIterator - next",
        //     .src = @src(),
        // });
        // defer trace_zone.end();

        while (self.inner.next()) |res| {
            // when leaving a break and entering a non-break, set the start of a cluster
            if (self.prev_break and !res.is_break) {
                const cp_len: usize = std.unicode.utf8CodepointSequenceLength(res.cp) catch 1;
                self.start = self.inner.i - cp_len;
            }

            // a break marks the end of the current grapheme
            if (res.is_break) {
                const end = self.inner.i;
                const s = self.start;

                self.start = end;
                self.prev_break = true;

                return .{ .start = s, .len = end - s };
            }

            self.prev_break = false;
        }

        // flush the last grapheme if we ended mid-cluster
        if (!self.prev_break and self.start < self.str.len) {
            const s = self.start;
            const len = self.str.len - s;

            self.start = self.str.len;
            self.prev_break = true;

            return .{ .start = s, .len = len };
        }

        return null;
    }

    pub fn skip(self: *GraphemeClusterIterator) void {
        _ = self.next();
    }

    pub const GraphemeCluster = struct {
        start: usize,
        len: usize,

        pub inline fn bytes(self: GraphemeCluster, iter: *const GraphemeClusterIterator) []const u8 {
            return iter.str[self.start .. self.start + self.len];
        }
    };
};

pub const WidthMethod = zttio.gwidth.Method;

pub inline fn strWidth(str: []const u8, method: WidthMethod) usize {
    const trace_zone = tracy.Zone.begin(.{
        .name = "[Unicode]: strWidth",
        .src = @src(),
    });
    defer trace_zone.end();

    return zttio.gwidth.gwidth(str, method);
}
