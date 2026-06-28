const argv = @import("../argv.zig");
const io = @import("../io.zig");
const path = @import("../path.zig");
const libc = @import("libc");

pub fn run(parsed: *const argv.Parsed) void {
    const dir_path = parsed.positionalAt(0) orelse {
        io.writeStr("rmdir: usage: rmdir /path\n");
        return;
    };

    var pathbuf: [128]u8 = undefined;
    const resolved = path.resolve(dir_path, &pathbuf) orelse {
        io.writeStr("rmdir: path too long\n");
        return;
    };

    if (libc.syscall.rmdir(@ptrCast(resolved.ptr)) < 0) {
        io.writeStr("rmdir: failed\n");
        return;
    }
    io.writeStr("rmdir: ok\n");
}
