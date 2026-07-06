const io = @import("../io.zig");
const libc = @import("libc");

pub fn run() void {
    libc.io.writeSignedDecimal(libc.process.getpid());
    io.writeNewline();
}
