const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;

const std = @import("std");
const linux = std.os.linux;
const ulib = @import("ulib");

const default_host = [4]u8{ 10, 0, 2, 2 };
const default_count: usize = 4;
const max_count: usize = 16;

/// Linux-target ping using `std.os.linux` sockets and `std.fmt` for output.
pub fn main(init: std.process.Init.Minimal) void {
    var host = default_host;
    var count = default_count;

    const argv = init.args.vector;
    var argi: usize = 1;
    while (argi < argv.len) : (argi += 1) {
        const arg = std.mem.span(argv[argi]);
        if (std.mem.eql(u8, arg, "-c")) {
            argi += 1;
            if (argi >= argv.len) {
                writeStr("usage: ping [-c count] [ip]\n");
                ulib.process.exit(1);
            }
            count = ulib.parse.parseDecimal(std.mem.span(argv[argi]), max_count) orelse {
                writeStr("ping: bad count\n");
                ulib.process.exit(1);
            };
            continue;
        }
        if (!ulib.ip.parseIpv4(arg, &host)) {
            writeStr("ping: bad address\n");
            ulib.process.exit(1);
        }
    }

    const fd_rc = linux.socket(linux.AF.INET, linux.SOCK.DGRAM, linux.IPPROTO.ICMP);
    if (@as(isize, @bitCast(fd_rc)) < 0) {
        writeStr("ping: socket failed\n");
        ulib.process.exit(1);
    }
    const fd: i32 = @intCast(fd_rc);

    var ip_buf: [16]u8 = undefined;
    const ip_str = ulib.ip.formatIpv4(host, &ip_buf) orelse "?";
    writeStr("PING ");
    writeStr(ip_str);
    writeStr(" 32 data bytes\n");

    var dest = linux.sockaddr.in{
        .port = 0,
        .addr = @bitCast(host),
    };

    const empty: [0]u8 = .{};
    var reply: [64]u8 = undefined;
    var transmitted: usize = 0;
    var received: usize = 0;
    var rtt_min_us: u64 = 0;
    var rtt_max_us: u64 = 0;
    var rtt_sum_us: u64 = 0;

    while (transmitted < count) : (transmitted += 1) {
        const start = monotonicUs();
        const send_rc = linux.sendto(fd, &empty, 0, 0, @ptrCast(&dest), @sizeOf(linux.sockaddr.in));
        if (@as(isize, @bitCast(send_rc)) < 0) {
            writeStr("ping: send failed\n");
            ulib.process.exit(1);
        }

        const recv_rc = linux.recvfrom(fd, &reply, reply.len, 0, null, null);
        if (@as(isize, @bitCast(recv_rc)) < 0) {
            writeStr("ping: ");
            writeStr(ip_str);
            writeStr(" timeout seq=");
            writeDecimal(transmitted);
            writeStr("\n");
            continue;
        }
        const n: usize = @intCast(recv_rc);

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
        writeDecimal(n);
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
        ulib.process.exit(0);
    }

    ulib.process.exit(1);
}

fn writeDecimal(n: usize) void {
    var buf: [24]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{n}) catch return;
    writeStr(text);
}

fn writeMillis(us: u64) void {
    var buf: [24]u8 = undefined;
    const ms = us / 1000;
    const frac: u16 = @intCast(us % 1000);
    const text = std.fmt.bufPrint(&buf, "{d}.{d:0>3}", .{ ms, frac }) catch return;
    writeStr(text);
}

fn monotonicUs() u64 {
    return ulib.time.monotonicUs();
}

fn elapsedSinceUs(start: u64) u64 {
    return ulib.time.elapsedUs(start, monotonicUs());
}

fn writeStr(s: []const u8) void {
    if (s.len == 0) return;
    _ = linux.write(linux.STDOUT_FILENO, s.ptr, s.len);
}
