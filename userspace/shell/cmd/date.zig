const io = @import("../io.zig");
const libc = @import("libc");

var timespec_storage: libc.syscall.Timespec = .{ .tv_sec = 0, .tv_nsec = 0 };

pub fn run() void {
    if (libc.syscall.clock_gettime(libc.syscall.CLOCK_REALTIME, &timespec_storage) < 0) {
        io.writeStr("date: failed\n");
        return;
    }
    printUtc(timespec_storage.tv_sec);
    io.writeStr(" UTC\n");
}

fn printUtc(sec: i64) void {
    const parts = civilFromUnix(sec);
    printPadded4(@intCast(parts.year));
    io.writeChar('-');
    printPadded2(parts.month);
    io.writeChar('-');
    printPadded2(parts.day);
    io.writeChar(' ');
    printPadded2(parts.hour);
    io.writeChar(':');
    printPadded2(parts.minute);
    io.writeChar(':');
    printPadded2(parts.second);
}

const Civil = struct {
    year: i32,
    month: i32,
    day: i32,
    hour: i32,
    minute: i32,
    second: i32,
};

fn civilFromUnix(sec: i64) Civil {
    var t = sec;
    const second = @mod(t, 60);
    t = @divTrunc(t, 60);
    const minute = @mod(t, 60);
    t = @divTrunc(t, 60);
    const hour = @mod(t, 24);
    const z = @divTrunc(t, 24);

    const x = z + 719468;
    const era = @divFloor(x, 146097);
    const doe = @mod(x, 146097);
    const yoe = @divTrunc(doe - @divTrunc(doe, 1460) + @divTrunc(doe, 36524) - @divTrunc(doe, 146096), 365);
    var y: i64 = yoe + era * 400;
    const doy = doe - (365 * yoe + @divTrunc(yoe, 4) - @divTrunc(yoe, 100));
    const mp = @divTrunc(5 * doy + 2, 153);
    const d = doy - @divTrunc(153 * mp + 2, 5) + 1;
    const m = mp + if (mp < 10) @as(i64, 3) else @as(i64, -9);
    y += if (m <= 2) @as(i64, 1) else 0;

    return .{
        .year = @intCast(y),
        .month = @intCast(m),
        .day = @intCast(d),
        .hour = @intCast(hour),
        .minute = @intCast(minute),
        .second = @intCast(second),
    };
}

fn printPadded2(value: i32) void {
    if (value < 10) io.writeChar('0');
    printU32(@intCast(value));
}

fn printPadded4(value: u32) void {
    if (value < 1000) io.writeChar('0');
    if (value < 100) io.writeChar('0');
    if (value < 10) io.writeChar('0');
    printU32(value);
}

fn printU32(value: u32) void {
    var buf: [10]u8 = undefined;
    var n: usize = 0;
    var v = value;
    if (v == 0) {
        io.writeChar('0');
        return;
    }
    while (v > 0) : (n += 1) {
        buf[n] = @truncate('0' + @mod(v, 10));
        v /= 10;
    }
    while (n > 0) : (n -= 1) {
        io.writeChar(buf[n - 1]);
    }
}
