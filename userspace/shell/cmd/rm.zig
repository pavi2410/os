const argv = @import("../argv.zig");
const io = @import("../io.zig");
const path = @import("../path.zig");
const libc = @import("libc");

pub fn run(parsed: *const argv.Parsed) void {
    const file_path = parsed.positionalAt(0) orelse {
        io.writeStr("rm: usage: rm /path\n");
        return;
    };

    var pathbuf: [128]u8 = undefined;
    const resolved = path.resolve(file_path, &pathbuf) orelse {
        io.writeStr("rm: path too long\n");
        return;
    };

    if (libc.fs.unlink(@ptrCast(resolved.ptr)) < 0) {
        io.writeStr("rm: failed\n");
        return;
    }
    io.writeStr("rm: ok\n");
}
