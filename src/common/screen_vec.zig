const ScreenVec = @This();

pub const zero = ScreenVec{
    .x = 0,
    .y = 0,
};

x: u16,
y: u16,

pub fn inside(self: ScreenVec, other: ScreenVec) bool {
    return self.x < other.x and self.y < other.y;
}
