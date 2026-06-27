const io = @import("../io.zig");
const path = @import("../path.zig");
const libc = @import("libc");
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
    if (!path.copy(file_path, &pathbuf)) {
        io.writeStr("path too long\n");
        return;
    }

    const fd = libc.syscall.open(@ptrCast(&pathbuf), 0, 0);
    if (fd < 0) {
        io.writeStr("cat: open failed\n");
        return;
    }

    var buf: [512]u8 = undefined;
    var got_data = false;
    while (true) {
        const n = libc.syscall.read(@intCast(fd), &buf, buf.len);
        if (n <= 0) break;
        got_data = true;
        _ = libc.syscall.write(1, &buf, @intCast(n));
    }
    if (!got_data) io.writeStr("(empty)\n");
    _ = libc.syscall.close(@intCast(fd));
}
