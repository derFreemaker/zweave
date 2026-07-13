const zttio = @import("zttio");
pub const Key = zttio.Key;
pub const Mouse = zttio.Mouse;
pub const Winsize = zttio.Winsize;
pub const ColorScheme = zttio.Color.Scheme;

pub const Event = union(enum) {
    tick,

    key_press: Key,
    key_release: Key,
    paste: []const u8,
    mouse: Mouse,
    mouse_leave,

    on_focus,
    on_unfocus,
    win_focus_in,
    win_focus_out,

    winsize: Winsize,
    color_scheme: ColorScheme,

    pub inline fn from(event: zttio.Event) ?Event {
        return switch (event) {
            .key_press => |key| .{ .key_press = key },
            .key_release => |key| .{ .key_release = key },
            .paste => |paste| .{ .paste = paste },
            .mouse => |mouse| .{ .mouse = mouse },
            .mouse_leave => .mouse_leave,
            .focus_in => .win_focus_in,
            .focus_out => .win_focus_out,
            .winsize => |winsize| .{ .winsize = winsize },
            .color_scheme => |color_scheme| .{ .color_scheme = color_scheme },
            else => null,
        };
    }
};
