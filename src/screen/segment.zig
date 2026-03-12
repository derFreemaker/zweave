const std = @import("std");
const zttio = @import("zttio");

const Segment = @This();

hyperlink: ?zttio.ctlseqs.Hyperlink = null,

pub fn begin(self: *const Segment, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    if (self.hyperlink) |hyperlink| {
        try hyperlink.introduce(writer);
    }
}

pub fn end(self: *const Segment, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    if (self.hyperlink) |_| {
        try writer.writeAll(zttio.ctlseqs.Hyperlink.close);
    }
}
