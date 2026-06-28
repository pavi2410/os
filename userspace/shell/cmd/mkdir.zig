const argv = @import("../argv.zig");
const io = @import("../io.zig");
const path = @import("../path.zig");
const libc = @import("libc");

pub fn run(parsed: *const argv.Parsed) void {
    const dir_path = parsed.positionalAt(0) orelse {
        io.writeStr("mkdir: usage: mkdir /path\n");
        return;
    };

    var pathbuf: [128]u8 = undefined;
    if (!path.copy(dir_path, &pathbuf)) {
        io.writeStr("mkdir: path too long\n");
        return;
    }

    if (libc.syscall.mkdir(@ptrCast(&pathbuf), 0o755) < 0) {
        io.writeStr("mkdir: failed\n");
        return;
    }
    io.writeStr("mkdir: ok\n");
}
