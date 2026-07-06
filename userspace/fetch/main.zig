const freestanding_std = @import("freestanding_std");
const libc = @import("libc");

pub const std_options_debug_io = freestanding_std.std_options_debug_io;
pub const std_options = freestanding_std.std_options;

const default_port: u16 = 80;

export fn main(argc: usize, argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    if (argc < 2) {
        writeStr("usage: fetch <ip> [port]\n");
        libc.syscall.exit(1);
    }

    var host: [4]u8 = undefined;
    var port = default_port;
    if (!parseIpv4(cstr(argv[1]), &host)) {
        writeStr("fetch: only IPv4 addresses supported for now\n");
        libc.syscall.exit(1);
    }
    if (argc >= 3) {
        port = parsePort(cstr(argv[2])) orelse {
            writeStr("fetch: bad port\n");
            libc.syscall.exit(1);
        };
    }

    const fd = libc.syscall.socket(
        libc.syscall.AF_INET,
        libc.syscall.SOCK_STREAM,
        libc.syscall.IPPROTO_TCP,
    );
    if (fd < 0) {
        writeStr("fetch: socket failed\n");
        libc.syscall.exit(1);
    }

    var dest: libc.syscall.SockaddrIn = .{
        .family = libc.syscall.AF_INET,
        .port_be = @byteSwap(port),
        .addr = host,
    };

    if (libc.syscall.connect(@intCast(fd), &dest, @sizeOf(libc.syscall.SockaddrIn)) < 0) {
        writeStr("fetch: connect failed\n");
        libc.syscall.exit(1);
    }

    const request = "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n";
    if (libc.syscall.send(@intCast(fd), request.ptr, request.len, 0) < 0) {
        writeStr("fetch: send failed\n");
        libc.syscall.exit(1);
    }

    var buf: [512]u8 = undefined;
    var got_body = false;
    while (true) {
        const n = libc.syscall.recv(@intCast(fd), &buf, buf.len, 0);
        if (n == 0) break;
        if (n < 0) {
            writeStr("fetch: recv failed\n");
            libc.syscall.exit(1);
        }
        const chunk = buf[0..@intCast(n)];
        if (!got_body) {
            if (findBodyStart(chunk)) |body| {
                got_body = true;
                writeStr(body);
            }
        } else {
            writeStr(chunk);
        }
    }

    if (!got_body) writeStr("\n");
    libc.syscall.exit(0);
}

fn findBodyStart(data: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i + 3 < data.len) : (i += 1) {
        if (data[i] == '\r' and data[i + 1] == '\n' and data[i + 2] == '\r' and data[i + 3] == '\n') {
            return data[i + 4 ..];
        }
    }
    return null;
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

fn parsePort(s: []const u8) ?u16 {
    if (s.len == 0) return null;
    var value: u16 = 0;
    for (s) |ch| {
        if (ch < '0' or ch > '9') return null;
        value = @truncate(value * 10 + (ch - '0'));
    }
    return value;
}

fn writeStr(s: []const u8) void {
    _ = libc.syscall.write(1, s.ptr, s.len);
}
