const libc = @import("libc");

export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\ call main
        \\ mov $60, %%rax
        \\ xor %%rdi, %%rdi
        \\ syscall
        ::: .{ .memory = true });
    unreachable;
}

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
    while (true) {
        const n = libc.syscall.read(@intCast(fd), &buf, buf.len);
        if (n <= 0) break;
        _ = libc.syscall.write(1, &buf, @intCast(n));
    }
    _ = libc.syscall.close(@intCast(fd));
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
            writeStr("Built-ins: help, exit, pid, cat\n");
            writeStr("Programs in /BIN: hello, ...\n");
            writeStr("Use full paths with cat, e.g. cat /README.TXT\n");
        } else if (eql(cmd, "pid")) {
            printPid(libc.syscall.getpid());
        } else if (startsWith(cmd, "cat ")) {
            catFile(cmd[4..len]);
        } else if (startsWith(cmd, "/")) {
            writeStr("unknown command\n");
        } else {
            spawnProgram(cmd);
        }
    }
}
