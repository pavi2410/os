const cwd = @import("../cwd.zig");
const io = @import("../io.zig");

pub fn run() u8 {
    io.writeStr(cwd.get());
    io.writeNewline();
    return 0;
}
