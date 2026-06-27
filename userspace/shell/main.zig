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

fn startsWith(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    return eql(haystack[0..needle.len], needle);
}

fn trimNewline(buf: []u8, len: usize) usize {
    var end = len;
    while (end > 0 and (buf[end - 1] == '\n' or buf[end - 1] == '\r')) end -= 1;
    return end;
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

fn writeFile(path: []const u8, content: []const u8) void {
    var pathbuf: [128]u8 = undefined;
    if (path.len + 1 > pathbuf.len) {
        writeStr("write: path too long\n");
        return;
    }
    @memcpy(pathbuf[0..path.len], path);
    pathbuf[path.len] = 0;

    const fd = libc.syscall.open(@ptrCast(&pathbuf), O_WRONLY | O_CREAT | O_TRUNC, 0);
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

fn lsCommand(args: []const u8) void {
    var long = false;
    var path: []const u8 = "/";
    var i: usize = 0;

    while (i < args.len) {
        while (i < args.len and args[i] == ' ') i += 1;
        if (i >= args.len) break;

        if (args[i] == '-') {
            i += 1;
            while (i < args.len and args[i] != ' ') : (i += 1) {
                if (args[i] == 'l') long = true;
            }
            continue;
        }

        const start = i;
        while (i < args.len and args[i] != ' ') i += 1;
        path = args[start..i];
    }

    lsDir(path, long);
}

fn echoArgs(args: []const u8) void {
    var i: usize = 0;
    while (i < args.len and args[i] == ' ') i += 1;
    if (i < args.len) writeStr(args[i..]);
    writeStr("\n");
}

export fn main() callconv(.{ .x86_64_sysv = .{} }) void {
    writeStr("Simple shell ready. Type 'help'.\n");

    var line: [256]u8 = undefined;
    while (true) {
        writeStr(prompt);

        const n = libc.syscall.read(0, &line, line.len);
        if (n <= 0) continue;
        const len = trimNewline(&line, @intCast(n));
        const cmd = line[0..len];

        if (cmd.len == 0) continue;

        if (eql(cmd, "exit")) {
            libc.syscall.exit(0);
        } else if (eql(cmd, "help")) {
            writeStr("Built-ins: help, exit, pid, echo, cat, ls, write\n");
            writeStr("  echo [text...]  print a line\n");
            writeStr("  ls [-l] [path]  list directory ( -l = type + size )\n");
            writeStr("  write /path text...  create or replace a file\n");
            writeStr("Programs in /BIN: hello, ...\n");
            writeStr("Use full paths with cat, e.g. cat /README.TXT\n");
        } else if (eql(cmd, "pid")) {
            printPid(libc.syscall.getpid());
        } else if (eql(cmd, "echo")) {
            writeStr("\n");
        } else if (startsWith(cmd, "echo ")) {
            echoArgs(cmd[5..len]);
        } else if (eql(cmd, "ls")) {
            lsCommand("");
        } else if (startsWith(cmd, "ls ")) {
            lsCommand(cmd[3..len]);
        } else if (startsWith(cmd, "write ")) {
            const args = cmd[6..len];
            var i: usize = 0;
            while (i < args.len and args[i] == ' ') i += 1;
            const path_start = i;
            while (i < args.len and args[i] != ' ') i += 1;
            if (i == path_start) {
                writeStr("write: usage: write /path text...\n");
                continue;
            }
            const path = args[path_start..i];
            while (i < args.len and args[i] == ' ') i += 1;
            const content = args[i..len];
            writeFile(path, content);
        } else if (startsWith(cmd, "cat ")) {
            catFile(cmd[4..len]);
        } else if (startsWith(cmd, "/")) {
            writeStr("unknown command\n");
        } else {
            spawnProgram(cmd);
        }
    }
}
