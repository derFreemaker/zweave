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
    return self.x <= other.x and self.y <= other.y;
}

pub fn scale(self: ScreenVec, x: f32, y: f32) ScreenVec {
    return ScreenVec{
        .x = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.x)) * x)),
        .y = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.y)) * y)),
    };
}

/// clamps to zero
pub inline fn sub(self: ScreenVec, other: ScreenVec) ScreenVec {
    return ScreenVec{
        .x = self.x -| other.x,
        .y = self.y -| other.y,
    };
}

pub inline fn add(self: ScreenVec, other: ScreenVec) ScreenVec {
    return ScreenVec{
        .x = self.x + other.x,
        .y = self.y + other.y,
    };
}

pub inline fn min(self: ScreenVec, other: ScreenVec) ScreenVec {
    return ScreenVec{
        .x = @min(self.x, other.x),
        .y = @min(self.y, other.y),
    };
}

pub inline fn max(self: ScreenVec, other: ScreenVec) ScreenVec {
    return ScreenVec{
        .x = @max(self.x, other.x),
        .y = @max(self.y, other.y),
    };
}
