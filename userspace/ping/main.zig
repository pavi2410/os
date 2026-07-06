const freestanding_std = @import("freestanding_std");
const libc = @import("libc");

pub const std_options_debug_io = freestanding_std.std_options_debug_io;
pub const std_options = freestanding_std.std_options;

const default_host = [4]u8{ 10, 0, 2, 2 };
const default_count: usize = 4;
const max_count: usize = 16;

export fn main(argc: usize, argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    var host = default_host;
    var count = default_count;

    var argi: usize = 1;
    while (argi < argc) : (argi += 1) {
        const arg = libc.io.cstr(argv[argi]);
        if (libc.io.eql(arg, "-c")) {
            argi += 1;
            if (argi >= argc) {
                writeStr("usage: ping [-c count] [ip]\n");
                libc.syscall.exit(1);
            }
            count = parseCount(libc.io.cstr(argv[argi])) orelse {
                writeStr("ping: bad count\n");
                libc.syscall.exit(1);
            };
            continue;
        }
        if (!libc.ip.parseIpv4(arg, &host)) {
            writeStr("ping: bad address\n");
            libc.syscall.exit(1);
        }
    }

    const fd = libc.syscall.socket(
        libc.net.AF_INET,
        libc.net.SOCK_DGRAM,
        libc.net.IPPROTO_ICMP,
    );
    if (fd < 0) {
        writeStr("ping: socket failed\n");
        libc.syscall.exit(1);
    }

    var ip_buf: [16]u8 = undefined;
    const ip_str = libc.ip.formatIpv4(host, &ip_buf) orelse "?";
    writeStr("PING ");
    writeStr(ip_str);
    writeStr(" 32 data bytes\n");

    var dest = libc.net.sockaddrIn(host, 0);

    const empty: [0]u8 = .{};
    var reply: [64]u8 = undefined;
    var transmitted: usize = 0;
    var received: usize = 0;
    var rtt_min_us: u64 = 0;
    var rtt_max_us: u64 = 0;
    var rtt_sum_us: u64 = 0;

    while (transmitted < count) : (transmitted += 1) {
        const start = monotonicUs();
        if (libc.syscall.sendto(
            @intCast(fd),
            &empty,
            0,
            0,
            &dest,
            @sizeOf(libc.net.SockaddrIn),
        ) < 0) {
            writeStr("ping: send failed\n");
            libc.syscall.exit(1);
        }

        const n = libc.syscall.recvfrom(
            @intCast(fd),
            &reply,
            reply.len,
            0,
            null,
            null,
        );
        if (n < 0) {
            writeStr("ping: ");
            writeStr(ip_str);
            writeStr(" timeout seq=");
            writeDecimal(transmitted);
            writeStr("\n");
            continue;
        }

        const elapsed_us = elapsedSinceUs(start);
        if (received == 0 or elapsed_us < rtt_min_us) rtt_min_us = elapsed_us;
        if (elapsed_us > rtt_max_us) rtt_max_us = elapsed_us;
        rtt_sum_us += elapsed_us;
        received += 1;

        writeStr("ping: ");
        writeStr(ip_str);
        writeStr(" reply seq=");
        writeDecimal(transmitted);
        writeStr(" bytes=");
        writeDecimal(@intCast(n));
        writeStr(" time=");
        writeMillis(elapsed_us);
        writeStr(" ms\n");
    }

    writeStr("\n--- ");
    writeStr(ip_str);
    writeStr(" ping statistics ---\n");
    writeDecimal(transmitted);
    writeStr(" packets transmitted, ");
    writeDecimal(received);
    writeStr(" received, ");
    writeDecimal(if (transmitted == 0) 0 else ((transmitted - received) * 100) / transmitted);
    writeStr("% packet loss\n");

    if (received > 0) {
        writeStr("rtt min/avg/max = ");
        writeMillis(rtt_min_us);
        writeStr("/");
        writeMillis(rtt_sum_us / received);
        writeStr("/");
        writeMillis(rtt_max_us);
        writeStr(" ms\n");
        libc.syscall.exit(0);
    }

    libc.syscall.exit(1);
}

fn parseCount(s: []const u8) ?usize {
    if (s.len == 0) return null;
    var value: usize = 0;
    for (s) |ch| {
        if (ch < '0' or ch > '9') return null;
        value = value * 10 + (ch - '0');
        if (value > max_count) return null;
    }
    if (value == 0) return null;
    return value;
}

fn writeDecimal(n: usize) void {
    var buf: [20]u8 = undefined;
    if (n == 0) {
        writeStr("0");
        return;
    }
    var value = n;
    var len: usize = 0;
    while (value > 0) : (len += 1) {
        buf[len] = '0' + @as(u8, @truncate(value % 10));
        value /= 10;
    }
    while (len > 0) {
        len -= 1;
        var ch: [1]u8 = .{buf[len]};
        writeStr(&ch);
    }
}

fn writeMillis(us: u64) void {
    writeDecimal(@intCast(us / 1000));
    writeStr(".");
    const frac: u16 = @intCast(us % 1000);
    var buf: [3]u8 = .{
        '0' + @as(u8, @intCast(frac / 100)),
        '0' + @as(u8, @intCast((frac / 10) % 10)),
        '0' + @as(u8, @intCast(frac % 10)),
    };
    writeStr(&buf);
}

fn monotonicUs() u64 {
    var ts: libc.syscall.Timespec = undefined;
    if (libc.syscall.clock_gettime(libc.syscall.CLOCK_MONOTONIC, &ts) < 0) return 0;
    return timespecUs(ts);
}

fn elapsedSinceUs(start: u64) u64 {
    const now = monotonicUs();
    if (now < start) return 0;
    return now - start;
}

fn timespecUs(ts: libc.syscall.Timespec) u64 {
    if (ts.tv_sec < 0 or ts.tv_nsec < 0) return 0;
    return @as(u64, @intCast(ts.tv_sec)) * 1_000_000 + @as(u64, @intCast(ts.tv_nsec)) / 1000;
}

fn writeStr(s: []const u8) void {
    libc.io.writeStr(s);
}
