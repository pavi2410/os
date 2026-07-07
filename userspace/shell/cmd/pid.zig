const io = @import("../io.zig");
const ulib = @import("ulib");

pub fn run() void {
    ulib.io.writeSignedDecimal(ulib.process.getpid());
    io.writeNewline();
}
