const io = @import("../io.zig");
const libc = @import("libc");

const bin_dir = "/BIN/";

pub fn run(name: []const u8) void {
    var pathbuf: [128]u8 = undefined;
    if (!formatBinPath(name, &pathbuf)) {
        io.writeStr("spawn failed\n");
        return;
    }

    const rc = libc.syscall.spawn(@ptrCast(&pathbuf));
    if (rc < 0) {
        io.writeStr("spawn failed\n");
    }
}

fn toUpper(ch: u8) u8 {
    if (ch >= 'a' and ch <= 'z') return ch - 32;
    return ch;
}

/// Map a shell command name to `/BIN/NAME` (FAT 8.3 names are uppercase).
/// There is no PATH yet — programs must live under /BIN on the disk.
fn formatBinPath(name: []const u8, out: []u8) bool {
    var i: usize = 0;
    for (bin_dir) |ch| {
        if (i >= out.len - 1) return false;
        out[i] = ch;
        i += 1;
    }
    for (name) |ch| {
        if (ch == ' ' or ch == '/') return false;
        if (i >= out.len - 1) return false;
        out[i] = toUpper(ch);
        i += 1;
    }
    if (i == bin_dir.len) return false;
    out[i] = 0;
    return true;
}
