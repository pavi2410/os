const cwd = @import("../cwd.zig");
const io = @import("../io.zig");

pub fn run() void {
    io.writeStr(cwd.get());
    io.writeNewline();
}
