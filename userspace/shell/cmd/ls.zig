const argv = @import("../argv.zig");
const io = @import("../io.zig");
const path = @import("../path.zig");
const libc = @import("libc");

const S_IFDIR: u32 = 0o040000;

pub fn run(parsed: *const argv.Parsed) void {
    const dir = parsed.positionalAt(0) orelse "/";
    lsDir(dir, parsed.hasFlag('l'));
}

fn lsDir(dir: []const u8, long: bool) void {
    var pathbuf: [128]u8 = undefined;
    if (!path.copy(dir, &pathbuf)) {
        io.writeStr("ls: path too long\n");
        return;
    }

    var buf: [1024]u8 = undefined;
    const n = libc.syscall.listdir(@ptrCast(&pathbuf), &buf, buf.len);
    if (n < 0) {
        io.writeStr("ls: failed\n");
        return;
    }
    if (!long) {
        _ = libc.syscall.write(1, &buf, @intCast(n));
        return;
    }

    var off: usize = 0;
    while (off < @as(usize, @intCast(n))) {
        var end = off;
        while (end < @as(usize, @intCast(n)) and buf[end] != '\n') end += 1;
        const name = buf[off..end];
        if (name.len > 0) printLongEntry(dir, name);
        off = end + 1;
    }
}

fn printLongEntry(dir: []const u8, name: []const u8) void {
    var pathbuf: [128]u8 = undefined;
    if (!path.join(dir, name, &pathbuf)) return;

    var st: libc.syscall.Stat = .{};
    if (libc.syscall.stat(@ptrCast(&pathbuf), &st) < 0) return;

    writeEntryType(st.st_mode);
    printSizePadded(@intCast(@max(st.st_size, 0)));
    io.writeStr(" ");
    io.writeStr(name);
    io.writeNewline();
}

fn writeEntryType(mode: u32) void {
    if (mode & S_IFDIR != 0) {
        io.writeStr("dir  ");
    } else {
        io.writeStr("file ");
    }
}

fn printSizePadded(value: u64) void {
    var buf: [16]u8 = undefined;
    var n: usize = 0;
    var v = value;
    if (v == 0) {
        io.writeStr("       0");
        return;
    }
    while (v > 0) : (n += 1) {
        buf[n] = @truncate('0' + @mod(v, 10));
        v /= 10;
    }
    var pad: usize = 0;
    if (n < 8) pad = 8 - n;
    while (pad > 0) : (pad -= 1) io.writeStr(" ");
    while (n > 0) : (n -= 1) {
        io.writeChar(buf[n - 1]);
    }
}
