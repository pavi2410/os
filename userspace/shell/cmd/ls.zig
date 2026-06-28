const argv = @import("../argv.zig");
const io = @import("../io.zig");
const path = @import("../path.zig");
const libc = @import("libc");

const S_IFDIR: u32 = 0o040000;
const O_RDONLY: u32 = 0;

const Dirent64 = extern struct {
    d_ino: u64,
    d_off: i64,
    d_reclen: u16,
    d_type: u8,
};

const dirent_name_off: usize = 19;

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

    const fd = libc.syscall.open(@ptrCast(&pathbuf), O_RDONLY, 0);
    if (fd < 0) {
        io.writeStr("ls: failed\n");
        return;
    }
    defer _ = libc.syscall.close(@intCast(fd));

    var buf: [1024]u8 = undefined;
    while (true) {
        const n = libc.syscall.getdents64(@intCast(fd), &buf, buf.len);
        if (n <= 0) break;
        if (long) {
            emitLongNames(dir, buf[0..@intCast(n)]);
        } else {
            emitShortNames(buf[0..@intCast(n)]);
        }
    }
}

fn emitShortNames(data: []const u8) void {
    var off: usize = 0;
    while (off + dirent_name_off <= data.len) {
        const hdr: *const Dirent64 = @ptrCast(@alignCast(data.ptr + off));
        const reclen = hdr.d_reclen;
        if (reclen < dirent_name_off or off + reclen > data.len) break;

        const name_start = off + dirent_name_off;
        var name_len: usize = 0;
        while (name_len < reclen - dirent_name_off and data[name_start + name_len] != 0) {
            name_len += 1;
        }
        const name = data[name_start .. name_start + name_len];
        if (name.len > 0) {
            io.writeStr(name);
            io.writeNewline();
        }
        off += reclen;
    }
}

fn emitLongNames(dir: []const u8, data: []const u8) void {
    var off: usize = 0;
    while (off + dirent_name_off <= data.len) {
        const hdr: *const Dirent64 = @ptrCast(@alignCast(data.ptr + off));
        const reclen = hdr.d_reclen;
        if (reclen < dirent_name_off or off + reclen > data.len) break;

        const name_start = off + dirent_name_off;
        var name_len: usize = 0;
        while (name_len < reclen - dirent_name_off and data[name_start + name_len] != 0) {
            name_len += 1;
        }
        const name = data[name_start .. name_start + name_len];
        if (name.len > 0) printLongEntry(dir, name);
        off += reclen;
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
