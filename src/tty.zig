const builtin = @import("builtin");

const zttio = @import("zttio");

pub const Tty = zttio.Tty(.{
    .run_own_thread = !builtin.single_threaded,
});
