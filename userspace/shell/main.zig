const argv = @import("argv.zig");
const libc = @import("libc");

const prompt = "os> ";
const bin_dir = "/BIN/";

fn writeStr(s: []const u8) void {
    _ = libc.syscall.write(1, s.ptr, s.len);
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x != y) return false;
    }
    return true;
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

fn spawnProgram(name: []const u8) void {
    var pathbuf: [128]u8 = undefined;
    if (!formatBinPath(name, &pathbuf)) {
        writeStr("spawn failed\n");
        return;
    }

    const rc = libc.syscall.spawn(@ptrCast(&pathbuf));
    if (rc < 0) {
        writeStr("spawn failed\n");
    }
}

fn printPid(pid: isize) void {
    var buf: [16]u8 = undefined;
    var n: usize = 0;
    var value: u64 = @intCast(@max(pid, 0));
    if (pid < 0) {
        buf[0] = '-';
        n = 1;
        value = @intCast(-pid);
    }
    var digits: [16]u8 = undefined;
    var count: usize = 0;
    if (value == 0) {
        digits[0] = '0';
        count = 1;
    } else {
        while (value > 0) : (count += 1) {
            digits[count] = @truncate('0' + @mod(value, 10));
            value /= 10;
        }
    }
    while (count > 0) : (count -= 1) {
        buf[n] = digits[count - 1];
        n += 1;
    }
    buf[n] = '\n';
    writeStr(buf[0 .. n + 1]);
}

fn catFile(path: []const u8) void {
    var pathbuf: [128]u8 = undefined;
    if (path.len + 1 > pathbuf.len) {
        writeStr("path too long\n");
        return;
    }
    @memcpy(pathbuf[0..path.len], path);
    pathbuf[path.len] = 0;

    const fd = libc.syscall.open(@ptrCast(&pathbuf), 0, 0);
    if (fd < 0) {
        writeStr("cat: open failed\n");
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
    if (!got_data) writeStr("(empty)\n");
    _ = libc.syscall.close(@intCast(fd));
}

const O_WRONLY: u32 = 1;
const O_CREAT: u32 = 0o100;
const O_TRUNC: u32 = 0o1000;
const O_APPEND: u32 = 0o2000;

fn writeFile(path: []const u8, content: []const u8, append: bool) void {
    var pathbuf: [128]u8 = undefined;
    if (path.len + 1 > pathbuf.len) {
        writeStr("write: path too long\n");
        return;
    }
    @memcpy(pathbuf[0..path.len], path);
    pathbuf[path.len] = 0;

    var open_flags: u32 = O_WRONLY | O_CREAT;
    if (append) {
        open_flags |= O_APPEND;
    } else {
        open_flags |= O_TRUNC;
    }

    const fd = libc.syscall.open(@ptrCast(&pathbuf), open_flags, 0);
    if (fd < 0) {
        writeStr("write: open failed\n");
        return;
    }

    if (content.len > 0) {
        const n = libc.syscall.write(@intCast(fd), content.ptr, content.len);
        if (n < 0) {
            writeStr("write: I/O failed\n");
            _ = libc.syscall.close(@intCast(fd));
            return;
        }
    }
    _ = libc.syscall.close(@intCast(fd));
    writeStr("write: ok\n");
}

const S_IFDIR: u32 = 0o040000;

fn joinPath(dir: []const u8, name: []const u8, out: []u8) bool {
    if (dir.len == 0 or name.len == 0) return false;
    var len: usize = 0;
    if (eql(dir, "/")) {
        if (1 + name.len + 1 > out.len) return false;
        out[0] = '/';
        len = 1;
    } else {
        if (dir.len + 1 + name.len + 1 > out.len) return false;
        @memcpy(out[0..dir.len], dir);
        out[dir.len] = '/';
        len = dir.len + 1;
    }
    @memcpy(out[len .. len + name.len], name);
    out[len + name.len] = 0;
    return true;
}

fn writeEntryType(mode: u32) void {
    if (mode & S_IFDIR != 0) {
        writeStr("dir  ");
    } else {
        writeStr("file ");
    }
}

fn printSizePadded(value: u64) void {
    var buf: [16]u8 = undefined;
    var n: usize = 0;
    var v = value;
    if (v == 0) {
        writeStr("       0");
        return;
    }
    while (v > 0) : (n += 1) {
        buf[n] = @truncate('0' + @mod(v, 10));
        v /= 10;
    }
    var pad: usize = 0;
    if (n < 8) pad = 8 - n;
    while (pad > 0) : (pad -= 1) writeStr(" ");
    while (n > 0) : (n -= 1) {
        var ch: [1]u8 = .{buf[n - 1]};
        writeStr(&ch);
    }
}

fn printLongEntry(path: []const u8, name: []const u8) void {
    var pathbuf: [128]u8 = undefined;
    if (!joinPath(path, name, &pathbuf)) return;

    var st: libc.syscall.Stat = .{};
    if (libc.syscall.stat(@ptrCast(&pathbuf), &st) < 0) return;

    writeEntryType(st.st_mode);
    printSizePadded(@intCast(@max(st.st_size, 0)));
    writeStr(" ");
    writeStr(name);
    writeStr("\n");
}

fn lsDir(path: []const u8, long: bool) void {
    var pathbuf: [128]u8 = undefined;
    if (path.len + 1 > pathbuf.len) {
        writeStr("ls: path too long\n");
        return;
    }
    @memcpy(pathbuf[0..path.len], path);
    pathbuf[path.len] = 0;

    var buf: [1024]u8 = undefined;
    const n = libc.syscall.listdir(@ptrCast(&pathbuf), &buf, buf.len);
    if (n < 0) {
        writeStr("ls: failed\n");
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
        if (name.len > 0) printLongEntry(path, name);
        off = end + 1;
    }
}

fn echoCommand(parsed: *const argv.Parsed) void {
    var buf: [192]u8 = undefined;
    const text = parsed.joinPositionalsFrom(&buf, 0) catch {
        writeStr("echo: text too long\n");
        return;
    };
    writeStr(text);
    writeStr("\n");
}

export fn main() callconv(.{ .x86_64_sysv = .{} }) void {
    writeStr("Simple shell ready. Type 'help'.\n");

    var line: [256]u8 = undefined;
    while (true) {
        writeStr(prompt);

        const n = libc.syscall.read(0, &line, line.len);
        if (n <= 0) continue;

        const parsed = argv.parse(&line, @intCast(n)) catch {
            writeStr("too many arguments\n");
            continue;
        };
        if (parsed.argc == 0) continue;

        const cmd = parsed.cmd().?;

        if (eql(cmd, "exit")) {
            libc.syscall.exit(0);
        } else if (eql(cmd, "help")) {
            writeStr("Built-ins: help, exit, pid, echo, cat, ls, write\n");
            writeStr("  echo [text...]  print a line\n");
            writeStr("  ls [-l] [path]  list directory ( -l = type + size )\n");
            writeStr("  write [-a] /path text...  create, replace (-a append)\n");
            writeStr("Programs in /BIN: hello, ...\n");
            writeStr("Use full paths with cat, e.g. cat /README.TXT\n");
        } else if (eql(cmd, "pid")) {
            printPid(libc.syscall.getpid());
        } else if (eql(cmd, "echo")) {
            if (parsed.positionalAt(0) == null) {
                writeStr("\n");
            } else {
                echoCommand(&parsed);
            }
        } else if (eql(cmd, "ls")) {
            const path = parsed.positionalAt(0) orelse "/";
            lsDir(path, parsed.hasFlag('l'));
        } else if (eql(cmd, "write")) {
            const path = parsed.positionalAt(0) orelse {
                writeStr("write: usage: write [-a] /path text...\n");
                continue;
            };
            var content_buf: [192]u8 = undefined;
            const content = parsed.joinPositionalsFrom(&content_buf, 1) catch {
                writeStr("write: text too long\n");
                continue;
            };
            writeFile(path, content, parsed.hasFlag('a'));
        } else if (eql(cmd, "cat")) {
            const path = parsed.positionalAt(0) orelse {
                writeStr("cat: usage: cat /path\n");
                continue;
            };
            catFile(path);
        } else if (cmd.len > 0 and cmd[0] == '/') {
            writeStr("unknown command\n");
        } else {
            spawnProgram(cmd);
        }
    }
}
