const io = @import("../io.zig");
const path = @import("../path.zig");
const ulib = @import("ulib");
const argv = @import("../argv.zig");

pub fn run(parsed: *const argv.Parsed) void {
    const file_path = parsed.positionalAt(0) orelse {
        io.writeStr("cat: usage: cat /path\n");
        return;
    };
    catFile(file_path);
}

fn catFile(file_path: []const u8) void {
    var pathbuf: [128]u8 = undefined;
    const resolved = path.resolve(file_path, &pathbuf) orelse {
        io.writeStr("path too long\n");
        return;
    };

    const fd = ulib.fs.open(@ptrCast(resolved.ptr), ulib.fs.O_RDONLY, 0);
    if (fd < 0) {
        io.writeStr("cat: open failed\n");
        return;
    }

    var buf: [512]u8 = undefined;
    var got_data = false;
    while (true) {
        const n = ulib.fs.read(@intCast(fd), &buf, buf.len);
        if (n <= 0) break;
        got_data = true;
        _ = ulib.fs.write(1, &buf, @intCast(n));
    }
    if (!got_data) io.writeStr("(empty)\n");
    _ = ulib.fs.close(@intCast(fd));
}
