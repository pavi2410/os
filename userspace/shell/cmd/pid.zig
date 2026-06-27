const io = @import("../io.zig");
const libc = @import("libc");

pub fn run() void {
    printPid(libc.syscall.getpid());
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
    io.writeStr(buf[0 .. n + 1]);
}
