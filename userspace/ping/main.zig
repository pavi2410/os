const freestanding_std = @import("freestanding_std");
const libc = @import("libc");

pub const std_options_debug_io = freestanding_std.std_options_debug_io;
pub const std_options = freestanding_std.std_options;

const default_host = [4]u8{ 10, 0, 2, 2 };

export fn main(argc: usize, argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    var host = default_host;

    if (argc >= 2) {
        const arg = cstr(argv[1]);
        if (!parseIpv4(arg, &host)) {
            writeStr("ping: bad address\n");
            libc.syscall.exit(1);
        }
    }

    const fd = libc.syscall.socket(
        libc.syscall.AF_INET,
        libc.syscall.SOCK_DGRAM,
        libc.syscall.IPPROTO_ICMP,
    );
    if (fd < 0) {
        writeStr("ping: socket failed\n");
        libc.syscall.exit(1);
    }

    var dest: libc.syscall.SockaddrIn = .{
        .family = libc.syscall.AF_INET,
        .port_be = 0,
        .addr = host,
    };

    const empty: [0]u8 = .{};
    if (libc.syscall.sendto(
        @intCast(fd),
        &empty,
        0,
        0,
        &dest,
        @sizeOf(libc.syscall.SockaddrIn),
    ) < 0) {
        writeStr("ping: send failed\n");
        libc.syscall.exit(1);
    }

    var reply: [64]u8 = undefined;
    const n = libc.syscall.recvfrom(
        @intCast(fd),
        &reply,
        reply.len,
        0,
        null,
        null,
    );
    if (n < 0) {
        writeStr("ping: timeout\n");
        libc.syscall.exit(1);
    }

    var ip_buf: [16]u8 = undefined;
    const ip_str = formatIpv4(host, &ip_buf) orelse "?";
    writeStr("ping: ");
    writeStr(ip_str);
    writeStr(" reply (");
    writeDecimal(@intCast(n));
    writeStr(" bytes)\n");
    libc.syscall.exit(0);
}

fn cstr(ptr: [*]u8) []const u8 {
    var len: usize = 0;
    while (len < 256) : (len += 1) {
        if (ptr[len] == 0) return ptr[0..len];
    }
    return ptr[0..256];
}

fn parseIpv4(s: []const u8, out: *[4]u8) bool {
    var part: u8 = 0;
    var idx: usize = 0;
    var i: usize = 0;
    while (i <= s.len) : (i += 1) {
        if (i == s.len or s[i] == '.') {
            if (idx >= 4) return false;
            out[idx] = part;
            idx += 1;
            part = 0;
            continue;
        }
        const ch = s[i];
        if (ch < '0' or ch > '9') return false;
        part = @truncate(part * 10 + (ch - '0'));
        if (part > 255) return false;
    }
    return idx == 4;
}

fn formatIpv4(addr: [4]u8, out: []u8) ?[]const u8 {
    var pos: usize = 0;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        if (i > 0) {
            if (pos >= out.len) return null;
            out[pos] = '.';
            pos += 1;
        }
        pos += writeU8Decimal(addr[i], out[pos..]);
    }
    return out[0..pos];
}

fn writeU8Decimal(n: u8, out: []u8) usize {
    if (n >= 100) {
        out[0] = '0' + (n / 100);
        out[1] = '0' + ((n / 10) % 10);
        out[2] = '0' + (n % 10);
        return 3;
    }
    if (n >= 10) {
        out[0] = '0' + (n / 10);
        out[1] = '0' + (n % 10);
        return 2;
    }
    out[0] = '0' + n;
    return 1;
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

fn writeStr(s: []const u8) void {
    _ = libc.syscall.write(1, s.ptr, s.len);
}
