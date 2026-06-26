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
            writeStr("Built-ins: help, exit, pid\n");
            writeStr("Programs: hello\n");
        } else if (eql(cmd, "pid")) {
            printPid(libc.syscall.getpid());
        } else if (startsWith(cmd, "hello")) {
            const path = "/hello";
            const rc = libc.syscall.spawn(path);
            if (rc < 0) {
                writeStr("spawn failed\n");
            }
        } else {
            writeStr("unknown command\n");
        }
    }
}
