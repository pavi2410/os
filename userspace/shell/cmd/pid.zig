const io = @import("../io.zig");
const ulib = @import("ulib");

pub fn run() u8 {
    ulib.io.writeSignedDecimal(ulib.process.getpid());
    io.writeNewline();
    return 0;
}
