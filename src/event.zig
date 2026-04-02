const zttio = @import("zttio");

pub const Event = union(enum) {
    tick,

    key_press: zttio.Key,
    key_release: zttio.Key,
    paste: []const u8,
    mouse: zttio.Mouse,
    mouse_leave,

    on_focus,
    focus_in,
    focus_out,

    winsize: zttio.Winsize,
    color_scheme: zttio.Color.Scheme,

    pub inline fn from(event: zttio.Event) ?Event {
        return switch (event) {
            .key_press => |key| .{ .key_press = key },
            .key_release => |key| .{ .key_release = key },
            .paste => |paste| .{ .paste = paste },
            .mouse => |mouse| .{ .mouse = mouse },
            .mouse_leave => .mouse_leave,
            .focus_in => .focus_in,
            .focus_out => .focus_out,
            .winsize => |winsize| .{ .winsize = winsize },
            .color_scheme => |color_scheme| .{ .color_scheme = color_scheme },
            else => null,
        };
    }
};
