const freestanding_std = @import("freestanding_std");
const libc = @import("libc");

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
    const query_len = buildQuery(qname, &query) catch {
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

fn buildQuery(name: []const u8, out: []u8) !usize {
    if (out.len < 18) return error.BufferTooSmall;
    @memset(out[0..18], 0);
    out[0] = 0x12;
    out[1] = 0x34;
    out[2] = 0x01;
    out[3] = 0x00;
    out[4] = 0x00;
    out[5] = 0x01;

    const name_len = try encodeName(name, out[12..]);
    const tail = 12 + name_len;
    if (tail + 4 > out.len) return error.BufferTooSmall;
    out[tail] = 0x00;
    out[tail + 1] = 0x01;
    out[tail + 2] = 0x00;
    out[tail + 3] = 0x01;
    return tail + 4;
}

fn encodeName(name: []const u8, out: []u8) !usize {
    if (name.len == 0 or name[0] == '.') return error.BadName;
    var written: usize = 0;
    var label_start: usize = 0;
    var i: usize = 0;
    while (i <= name.len) : (i += 1) {
        const at_end = i == name.len;
        const ch = if (at_end) '.' else name[i];
        if (ch == '.') {
            const label_len = i - label_start;
            if (label_len == 0 or label_len > 63) return error.BadName;
            if (written + 1 + label_len > out.len) return error.BufferTooSmall;
            out[written] = @intCast(label_len);
            @memcpy(out[written + 1 .. written + 1 + label_len], name[label_start..i]);
            written += 1 + label_len;
            label_start = i + 1;
            continue;
        }
        if (ch < '0' or (ch > '9' and ch < 'A') or (ch > 'Z' and ch < 'a') or ch > 'z') {
            if (ch != '-') return error.BadName;
        }
    }
    if (written + 1 > out.len) return error.BufferTooSmall;
    out[written] = 0;
    return written + 1;
}

fn printResult(qname: []const u8, pkt: []const u8) void {
    const qdcount = readU16(pkt, 4);
    const ancount = readU16(pkt, 6);

    writeStr("\n; <<>> OS dig <<>> ");
    writeStr(qname);
    writeStr("\n;; QUESTION SECTION:\n;");
    writeStr(qname);
    writeStr(".            IN  A\n");

    if (ancount == 0) {
        writeStr(";; ANSWER SECTION: (none)\n");
        return;
    }

    writeStr("\n;; ANSWER SECTION:\n");
    var off: usize = 12;
    var qi: usize = 0;
    while (qi < qdcount) : (qi += 1) {
        off = skipName(pkt, off) orelse return;
        off += 4;
        if (off > pkt.len) return;
    }

    var ai: usize = 0;
    while (ai < ancount) : (ai += 1) {
        const name_off = off;
        off = skipName(pkt, off) orelse return;
        if (off + 10 > pkt.len) return;
        const rtype = readU16(pkt, off);
        _ = readU32(pkt, off + 4);
        const rdlen = readU16(pkt, off + 8);
        off += 10;
        if (off + rdlen > pkt.len) return;

        if (rtype == 1 and rdlen == 4) {
            var name_buf: [128]u8 = undefined;
            const shown = formatName(pkt, name_off, &name_buf) orelse qname;
            writeStr(shown);
            writeStr(".    IN  A  ");
            writeIpv4(pkt[off .. off + 4]);
            writeStr("\n");
        }
        off += rdlen;
    }
}

fn formatName(pkt: []const u8, off: usize, out: []u8) ?[]const u8 {
    var pos = off;
    var len: usize = 0;
    var steps: usize = 0;
    while (steps < 128) : (steps += 1) {
        if (pos >= pkt.len) return null;
        const len_byte = pkt[pos];
        if (len_byte == 0) break;
        if ((len_byte & 0xC0) == 0xC0) {
            if (pos + 1 >= pkt.len) return null;
            const ptr = (@as(usize, len_byte & 0x3F) << 8) | pkt[pos + 1];
            pos = ptr;
            continue;
        }
        pos += 1;
        if (pos + len_byte > pkt.len) return null;
        if (len != 0) {
            if (len >= out.len) return null;
            out[len] = '.';
            len += 1;
        }
        if (len + len_byte > out.len) return null;
        @memcpy(out[len .. len + len_byte], pkt[pos .. pos + len_byte]);
        len += len_byte;
        pos += len_byte;
    }
    return out[0..len];
}

fn skipName(pkt: []const u8, off: usize) ?usize {
    var pos = off;
    var steps: usize = 0;
    while (steps < 128) : (steps += 1) {
        if (pos >= pkt.len) return null;
        const len_byte = pkt[pos];
        if (len_byte == 0) return pos + 1;
        if ((len_byte & 0xC0) == 0xC0) return pos + 2;
        pos += 1 + len_byte;
    }
    return null;
}

fn readU16(pkt: []const u8, off: usize) u16 {
    return (@as(u16, pkt[off]) << 8) | pkt[off + 1];
}

fn readU32(pkt: []const u8, off: usize) u32 {
    return (@as(u32, pkt[off]) << 24) |
        (@as(u32, pkt[off + 1]) << 16) |
        (@as(u32, pkt[off + 2]) << 8) |
        pkt[off + 3];
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
