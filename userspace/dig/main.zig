const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");
const dns_codec = @import("dns_codec");

const default_dns = [4]u8{ 10, 0, 2, 3 };
const dns_port: u16 = 53;

export fn main(argc: usize, argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    var dns_addr = default_dns;
    var name: ?[]const u8 = null;

    var i: usize = 1;
    while (i < argc) : (i += 1) {
        const arg = ulib.io.cstr(argv[i]);
        if (arg.len == 0) continue;
        if (arg[0] == '@') {
            if (!ulib.ip.parseIpv4(arg[1..], &dns_addr)) {
                ulib.io.writeStr("dig: bad server address\n");
                return 1;
            }
            continue;
        }
        name = arg;
        break;
    }

    const qname = name orelse {
        ulib.io.writeStr("usage: dig [@server] name\n");
        return 1;
    };

    var query: [256]u8 = undefined;
    const query_len = dns_codec.buildQuery(qname, &query) catch {
        ulib.io.writeStr("dig: bad name\n");
        return 1;
    };

    const fd = ulib.net.socket(ulib.net.AF_INET, ulib.net.SOCK_DGRAM, 0);
    if (fd < 0) {
        ulib.io.writeStr("dig: socket failed\n");
        return 1;
    }

    var dest = ulib.net.sockaddrIn(dns_addr, dns_port);

    if (ulib.net.sendto(
        @intCast(fd),
        &query,
        query_len,
        0,
        &dest,
    ) < 0) {
        ulib.io.writeStr("dig: send failed\n");
        return 1;
    }

    var reply: [512]u8 = undefined;
    const n = ulib.net.recvfrom(
        @intCast(fd),
        &reply,
        reply.len,
        0,
        null,
        null,
    );
    if (n < 12) {
        ulib.io.writeStr("dig: timeout\n");
        return 1;
    }

    printResult(qname, reply[0..@intCast(n)]);
    return 0;
}

fn printResult(qname: []const u8, pkt: []const u8) void {
    ulib.io.writeStr("\n; <<>> OS dig <<>> ");
    ulib.io.writeStr(qname);
    ulib.io.writeStr("\n;; QUESTION SECTION:\n;");
    ulib.io.writeStr(qname);
    ulib.io.writeStr(".            IN  A\n");

    if (dns_codec.answerCount(pkt) == 0) {
        ulib.io.writeStr(";; ANSWER SECTION: (none)\n");
        return;
    }

    ulib.io.writeStr("\n;; ANSWER SECTION:\n");

    var iter = dns_codec.answers(pkt) orelse return;
    while (iter.next()) |answer| {
        if (answer.rtype == 1 and answer.rdata.len == 4) {
            var name_buf: [128]u8 = undefined;
            const shown = dns_codec.formatName(pkt, answer.name_off, &name_buf) orelse qname;
            ulib.io.writeStr(shown);
            ulib.io.writeStr(".    IN  A  ");
            writeIpv4(answer.rdata);
            ulib.io.writeStr("\n");
        }
    }
}

fn writeIpv4(addr: []const u8) void {
    if (addr.len < 4) return;
    const ip: [4]u8 = .{ addr[0], addr[1], addr[2], addr[3] };
    var buf: [16]u8 = undefined;
    ulib.io.writeStr(ulib.ip.formatIpv4(ip, &buf) orelse "?");
}
