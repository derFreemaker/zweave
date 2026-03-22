const ScreenVec = @This();

pub const zero = ScreenVec{
    .x = 0,
    .y = 0,
};

x: u16,
y: u16,

pub inline fn isNull(self: ScreenVec) bool {
    return self.x == 0 or self.y == 0;
}

pub inline fn inside(self: ScreenVec, other: ScreenVec) bool {
    return self.x < other.x and self.y < other.y;
}
