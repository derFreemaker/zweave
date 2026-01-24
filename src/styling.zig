const zttio = @import("zttio");

const IndexT = @import("index.zig").IndexT;

pub const Style = zttio.Styling;

pub const Index = IndexT(Style, u16);
