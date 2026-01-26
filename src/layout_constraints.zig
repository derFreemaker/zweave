height: Constraint,
width: Constraint,

pub const Constraint = union(enum) {
    fixed: u16,
    percentage: f32,
    range: Range,

    pub const Range = struct {
        min: u16,
        max: u16,
    };
};
