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
    const resolved = path.resolve(dir_path, &pathbuf) orelse {
        io.writeStr("mkdir: path too long\n");
        return;
    };

    if (libc.fs.mkdir(@ptrCast(resolved.ptr), 0o755) < 0) {
        io.writeStr("mkdir: failed\n");
        return;
    }
    io.writeStr("mkdir: ok\n");
}
