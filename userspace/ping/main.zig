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
                libc.process.exit(1);
            }
            count = libc.parse.parseDecimal(libc.io.cstr(argv[argi]), max_count) orelse {
                writeStr("ping: bad count\n");
                libc.process.exit(1);
            };
            continue;
        }
        if (!libc.ip.parseIpv4(arg, &host)) {
            writeStr("ping: bad address\n");
            libc.process.exit(1);
        }
    }

    const fd = libc.net.socket(
        libc.net.AF_INET,
        libc.net.SOCK_DGRAM,
        libc.net.IPPROTO_ICMP,
    );
    if (fd < 0) {
        writeStr("ping: socket failed\n");
        libc.process.exit(1);
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
        if (libc.net.sendto(
            @intCast(fd),
            &empty,
            0,
            0,
            &dest,
        ) < 0) {
            writeStr("ping: send failed\n");
            libc.process.exit(1);
        }

        const n = libc.net.recvfrom(
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
        libc.process.exit(0);
    }

    libc.process.exit(1);
}

fn writeDecimal(n: usize) void {
    libc.io.writeDecimal(n);
}

fn writeMillis(us: u64) void {
    libc.io.writeMillis(us);
}

fn monotonicUs() u64 {
    return libc.time.monotonicUs();
}

fn elapsedSinceUs(start: u64) u64 {
    return libc.time.elapsedUs(start, monotonicUs());
}

fn writeStr(s: []const u8) void {
    libc.io.writeStr(s);
}
