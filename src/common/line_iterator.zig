const std = @import("std");

const LineIterator = @This();

buffer: []const u8,
index: usize,

pub fn init(buffer: []const u8) LineIterator {
    return LineIterator{
        .buffer = buffer,
        .index = 0,
    };
}

pub fn peek(self: *const LineIterator) ?Line {
    var idx = std.mem.indexOfAnyPos(u8, self.buffer, self.index, &.{ '\n', '\r' }) orelse {
        if (self.index < self.buffer.len) {
            return Line{
                .start = self.index,
                .end = self.buffer.len,
                .separator_len = 0,
            };
        }

        return null;
    };
    var separator_len: u8 = 1;
    if (self.buffer[idx] == '\r' and idx + 1 < self.buffer.len and self.buffer[idx + 1] == '\n') {
        idx += 1;
        separator_len += 1;
    }

    return Line{
        .start = self.index,
        .end = idx + 1,
        .separator_len = separator_len,
    };
}

pub inline fn toss(self: *LineIterator, line: Line) void {
    self.index += line.end - line.start;
}

pub const Line = struct {
    start: usize,
    end: usize,
    separator_len: u8,

    pub fn bytes(self: Line, line_iter: *LineIterator) []const u8 {
        return line_iter.buffer[self.start..self.end];
    }

    pub fn content(self: Line, line_iter: *LineIterator) []const u8 {
        return line_iter.buffer[self.start .. self.end - self.separator_len];
    }

    pub inline fn first(self: Line) bool {
        return self.start == 0;
    }

    pub inline fn last(self: Line) bool {
        return self.separator_len == 0;
    }
};
