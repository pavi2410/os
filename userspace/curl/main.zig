const freestanding_std = @import("freestanding_std");
const libc = @import("libc");
const target = @import("target.zig");

pub const std_options_debug_io = freestanding_std.std_options_debug_io;
pub const std_options = freestanding_std.std_options;

var norm_buf: [256]u8 = undefined;
var host_buf: [128]u8 = undefined;
var path_buf: [128]u8 = undefined;
var recv_buf: [512]u8 = undefined;

export fn main(argc: usize, argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    run(argc, argv);
}

noinline fn run(argc: usize, argv: [*][*]u8) void {
    if (argc < 2) {
        writeStr("usage: curl <url|host> [port]\n");
        libc.syscall.exit(1);
    }

    const arg = libc.io.cstr(argv[1]);
    const parsed = target.parse(arg, &norm_buf, &host_buf, &path_buf) catch {
        writeStr("curl: bad url\n");
        libc.syscall.exit(1);
    };

    var port = parsed.port;
    if (argc >= 3) {
        port = target.parsePort(libc.io.cstr(argv[2])) orelse {
            writeStr("curl: bad port\n");
            libc.syscall.exit(1);
        };
    }

    var host_ip: [4]u8 = undefined;
    if (target.ipv4Bytes(parsed.host, &host_ip)) {
        // literal IPv4
    } else if (!resolveName(parsed.host, &host_ip)) {
        writeStr("curl: could not resolve host\n");
        libc.syscall.exit(1);
    }

    httpGet(parsed.host, &host_ip, port, parsed.path);
}

noinline fn resolveName(name: []const u8, out: *[4]u8) bool {
    return libc.dns.resolveA(name, null, out);
}

noinline fn httpGet(host: []const u8, ip: *const [4]u8, port: u16, path: []const u8) void {
    const fd = libc.net.socket(
        libc.net.AF_INET,
        libc.net.SOCK_STREAM,
        libc.net.IPPROTO_TCP,
    );
    if (fd < 0) {
        writeStr("curl: socket failed\n");
        libc.syscall.exit(1);
    }

    var dest = libc.net.sockaddrIn(ip.*, port);

    if (libc.net.connect(@intCast(fd), &dest) < 0) {
        writeStr("curl: connect failed\n");
        libc.syscall.exit(1);
    }

    sendPart(@intCast(fd), "GET ");
    sendPart(@intCast(fd), path);
    sendPart(@intCast(fd), " HTTP/1.0\r\nHost: ");
    sendPart(@intCast(fd), host);
    sendPart(@intCast(fd), "\r\n\r\n");

    var got_body = false;
    while (true) {
        const n = libc.net.recv(@intCast(fd), &recv_buf, recv_buf.len, 0);
        if (n == 0) break;
        if (n < 0) {
            writeStr("curl: recv failed\n");
            libc.syscall.exit(1);
        }
        const chunk = recv_buf[0..@intCast(n)];
        if (!got_body) {
            if (target.findBodyStart(chunk)) |body| {
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

fn sendPart(fd: u32, bytes: []const u8) void {
    if (libc.net.send(fd, bytes.ptr, bytes.len, 0) < 0) {
        writeStr("curl: send failed\n");
        libc.syscall.exit(1);
    }
}

fn writeStr(s: []const u8) void {
    libc.io.writeStr(s);
}
