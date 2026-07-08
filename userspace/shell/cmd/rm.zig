const argv = @import("../argv.zig");
const io = @import("../io.zig");
const path = @import("../path.zig");
const ulib = @import("ulib");

pub fn run(parsed: *const argv.Parsed) u8 {
    const file_path = parsed.positionalAt(0) orelse {
        io.writeStr("rm: usage: rm /path\n");
        return 1;
    };

    var pathbuf: [128]u8 = undefined;
    const resolved = path.resolve(file_path, &pathbuf) orelse {
        io.writeStr("rm: path too long\n");
        return 1;
    };

    if (ulib.fs.unlink(@ptrCast(resolved.ptr)) < 0) {
        io.writeStr("rm: failed\n");
        return 1;
    }
    io.writeStr("rm: ok\n");
    return 0;
}
