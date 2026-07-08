const argv = @import("../argv.zig");
const io = @import("../io.zig");
const path = @import("../path.zig");
const ulib = @import("ulib");

pub fn run(parsed: *const argv.Parsed) u8 {
    const dir_path = parsed.positionalAt(0) orelse {
        io.writeStr("rmdir: usage: rmdir /path\n");
        return 1;
    };

    var pathbuf: [128]u8 = undefined;
    const resolved = path.resolve(dir_path, &pathbuf) orelse {
        io.writeStr("rmdir: path too long\n");
        return 1;
    };

    if (ulib.fs.rmdir(@ptrCast(resolved.ptr)) < 0) {
        io.writeStr("rmdir: failed\n");
        return 1;
    }
    io.writeStr("rmdir: ok\n");
    return 0;
}
