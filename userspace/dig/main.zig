const freestanding_std = @import("freestanding_std");
const libc = @import("libc");
const dns_codec = @import("dns_codec");

pub const std_options_debug_io = freestanding_std.std_options_debug_io;
pub const std_options = freestanding_std.std_options;

const default_dns = [4]u8{ 10, 0, 2, 3 };
const dns_port: u16 = 53;

export fn main(argc: usize, argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    var dns_addr = default_dns;
    var name: ?[]const u8 = null;

    var i: usize = 1;
    while (i < argc) : (i += 1) {
        const arg = libc.io.cstr(argv[i]);
        if (arg.len == 0) continue;
        if (arg[0] == '@') {
            if (!libc.ip.parseIpv4(arg[1..], &dns_addr)) {
                writeStr("dig: bad server address\n");
                libc.process.exit(1);
            }
            continue;
        }
        name = arg;
        break;
    }

    const qname = name orelse {
        writeStr("usage: dig [@server] name\n");
        libc.process.exit(1);
    };

    var query: [256]u8 = undefined;
    const query_len = dns_codec.buildQuery(qname, &query) catch {
        writeStr("dig: bad name\n");
        libc.process.exit(1);
    };

    const fd = libc.net.socket(libc.net.AF_INET, libc.net.SOCK_DGRAM, 0);
    if (fd < 0) {
        writeStr("dig: socket failed\n");
        libc.process.exit(1);
    }

    var dest = libc.net.sockaddrIn(dns_addr, dns_port);

    if (libc.net.sendto(
        @intCast(fd),
        &query,
        query_len,
        0,
        &dest,
    ) < 0) {
        writeStr("dig: send failed\n");
        libc.process.exit(1);
    }

    var reply: [512]u8 = undefined;
    const n = libc.net.recvfrom(
        @intCast(fd),
        &reply,
        reply.len,
        0,
        null,
        null,
    );
    if (n < 12) {
        writeStr("dig: timeout\n");
        libc.process.exit(1);
    }

    printResult(qname, reply[0..@intCast(n)]);
    libc.process.exit(0);
}

fn printResult(qname: []const u8, pkt: []const u8) void {
    writeStr("\n; <<>> OS dig <<>> ");
    writeStr(qname);
    writeStr("\n;; QUESTION SECTION:\n;");
    writeStr(qname);
    writeStr(".            IN  A\n");

    if (dns_codec.answerCount(pkt) == 0) {
        writeStr(";; ANSWER SECTION: (none)\n");
        return;
    }

    writeStr("\n;; ANSWER SECTION:\n");

    var iter = dns_codec.answers(pkt) orelse return;
    while (iter.next()) |answer| {
        if (answer.rtype == 1 and answer.rdata.len == 4) {
            var name_buf: [128]u8 = undefined;
            const shown = dns_codec.formatName(pkt, answer.name_off, &name_buf) orelse qname;
            writeStr(shown);
            writeStr(".    IN  A  ");
            writeIpv4(answer.rdata);
            writeStr("\n");
        }
    }
}

fn writeIpv4(addr: []const u8) void {
    if (addr.len < 4) return;
    const ip: [4]u8 = .{ addr[0], addr[1], addr[2], addr[3] };
    var buf: [16]u8 = undefined;
    writeStr(libc.ip.formatIpv4(ip, &buf) orelse "?");
}

fn writeStr(s: []const u8) void {
    libc.io.writeStr(s);
}
