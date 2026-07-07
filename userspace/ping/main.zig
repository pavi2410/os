const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;

const ulib = @import("ulib");

const default_host = [4]u8{ 10, 0, 2, 2 };
const default_count: usize = 4;
const max_count: usize = 16;

export fn main(argc: usize, argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    var host = default_host;
    var count = default_count;

    var argi: usize = 1;
    while (argi < argc) : (argi += 1) {
        const arg = ulib.io.cstr(argv[argi]);
        if (ulib.string.eql(arg, "-c")) {
            argi += 1;
            if (argi >= argc) {
                ulib.io.writeStr("usage: ping [-c count] [ip]\n");
                ulib.process.exit(1);
            }
            count = ulib.parse.parseDecimal(ulib.io.cstr(argv[argi]), max_count) orelse {
                ulib.io.writeStr("ping: bad count\n");
                ulib.process.exit(1);
            };
            continue;
        }
        if (!ulib.ip.parseIpv4(arg, &host)) {
            ulib.io.writeStr("ping: bad address\n");
            ulib.process.exit(1);
        }
    }

    const fd = ulib.net.socket(
        ulib.net.AF_INET,
        ulib.net.SOCK_DGRAM,
        ulib.net.IPPROTO_ICMP,
    );
    if (fd < 0) {
        ulib.io.writeStr("ping: socket failed\n");
        ulib.process.exit(1);
    }

    var ip_buf: [16]u8 = undefined;
    const ip_str = ulib.ip.formatIpv4(host, &ip_buf) orelse "?";
    ulib.io.writeStr("PING ");
    ulib.io.writeStr(ip_str);
    ulib.io.writeStr(" 32 data bytes\n");

    var dest = ulib.net.sockaddrIn(host, 0);

    const empty: [0]u8 = .{};
    var reply: [64]u8 = undefined;
    var transmitted: usize = 0;
    var received: usize = 0;
    var rtt_min_us: u64 = 0;
    var rtt_max_us: u64 = 0;
    var rtt_sum_us: u64 = 0;

    while (transmitted < count) : (transmitted += 1) {
        const start = ulib.time.monotonicUs();
        if (ulib.net.sendto(
            @intCast(fd),
            &empty,
            0,
            0,
            &dest,
        ) < 0) {
            ulib.io.writeStr("ping: send failed\n");
            ulib.process.exit(1);
        }

        const n = ulib.net.recvfrom(
            @intCast(fd),
            &reply,
            reply.len,
            0,
            null,
            null,
        );
        if (n < 0) {
            ulib.io.writeStr("ping: ");
            ulib.io.writeStr(ip_str);
            ulib.io.writeStr(" timeout seq=");
            ulib.io.writeDecimal(transmitted);
            ulib.io.writeStr("\n");
            continue;
        }

        const elapsed_us = ulib.time.elapsedUs(start, ulib.time.monotonicUs());
        if (received == 0 or elapsed_us < rtt_min_us) rtt_min_us = elapsed_us;
        if (elapsed_us > rtt_max_us) rtt_max_us = elapsed_us;
        rtt_sum_us += elapsed_us;
        received += 1;

        ulib.io.writeStr("ping: ");
        ulib.io.writeStr(ip_str);
        ulib.io.writeStr(" reply seq=");
        ulib.io.writeDecimal(transmitted);
        ulib.io.writeStr(" bytes=");
        ulib.io.writeDecimal(@intCast(n));
        ulib.io.writeStr(" time=");
        ulib.io.writeMillis(elapsed_us);
        ulib.io.writeStr(" ms\n");
    }

    ulib.io.writeStr("\n--- ");
    ulib.io.writeStr(ip_str);
    ulib.io.writeStr(" ping statistics ---\n");
    ulib.io.writeDecimal(transmitted);
    ulib.io.writeStr(" packets transmitted, ");
    ulib.io.writeDecimal(received);
    ulib.io.writeStr(" received, ");
    ulib.io.writeDecimal(if (transmitted == 0) 0 else ((transmitted - received) * 100) / transmitted);
    ulib.io.writeStr("% packet loss\n");

    if (received > 0) {
        ulib.io.writeStr("rtt min/avg/max = ");
        ulib.io.writeMillis(rtt_min_us);
        ulib.io.writeStr("/");
        ulib.io.writeMillis(rtt_sum_us / received);
        ulib.io.writeStr("/");
        ulib.io.writeMillis(rtt_max_us);
        ulib.io.writeStr(" ms\n");
        ulib.process.exit(0);
    }

    ulib.process.exit(1);
}
