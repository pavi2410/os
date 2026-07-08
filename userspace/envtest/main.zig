const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;

const ulib = @import("ulib");

export fn main(argc: usize, argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    if (ulib.environ.getenv("FOO", argc, @ptrCast(argv))) |value| {
        ulib.io.writeStr(value);
        ulib.io.writeStr("\n");
    } else {
        ulib.io.writeStr("(unset)\n");
    }
    return 0;
}
