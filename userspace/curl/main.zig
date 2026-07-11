const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");
const target = @import("target.zig");

var norm_buf: [256]u8 = undefined;
var host_buf: [128]u8 = undefined;
var path_buf: [128]u8 = undefined;
var recv_buf: [512]u8 = undefined;

export fn main(argc: usize, argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    if (argc < 2) {
        ulib.io.writeStr("usage: curl <url|host> [port]\n");
        return 1;
    }

    const arg = ulib.io.cstr(argv[1]);
    const parsed = target.parse(arg, &norm_buf, &host_buf, &path_buf) catch {
        ulib.io.writeStr("curl: bad url\n");
        return 1;
    };

    var port = parsed.port;
    if (argc >= 3) {
        port = ulib.parse.parsePort(ulib.io.cstr(argv[2])) orelse {
            ulib.io.writeStr("curl: bad port\n");
            return 1;
        };
    }

    var host_ip: [4]u8 = undefined;
    const resolved_ip: *const [4]u8 = switch (parsed.host) {
        .ipv4 => |addr| blk: {
            host_ip = addr;
            break :blk &host_ip;
        },
        .hostname => |name| blk: {
            if (!resolveName(name, &host_ip)) {
                ulib.io.writeStr("curl: could not resolve host\n");
                return 1;
            }
            break :blk &host_ip;
        },
    };

    return httpGet(parsed.authority, resolved_ip, port, parsed.path);
}

fn resolveName(name: []const u8, out: *[4]u8) bool {
    return ulib.dns.resolveA(name, null, out);
}

fn httpGet(host: []const u8, ip: *const [4]u8, port: u16, path: []const u8) u8 {
    const fd = ulib.net.socket(
        ulib.net.AF_INET,
        ulib.net.SOCK_STREAM,
        ulib.net.IPPROTO_TCP,
    );
    if (fd < 0) {
        ulib.io.writeStr("curl: socket failed\n");
        return 1;
    }

    var dest = ulib.net.sockaddrIn(ip.*, port);

    if (ulib.net.connect(@intCast(fd), &dest) < 0) {
        ulib.io.writeStr("curl: connect failed\n");
        return 1;
    }

    var request: [256]u8 = undefined;
    const request_len = target.buildRequest(host, path, &request) orelse {
        ulib.io.writeStr("curl: request too large\n");
        return 1;
    };
    if (sendPart(@intCast(fd), request[0..request_len]) != 0) return 1;

    var got_body = false;
    while (true) {
        const n = ulib.net.recv(@intCast(fd), &recv_buf, recv_buf.len, 0);
        if (n == 0) break;
        if (n < 0) {
            ulib.io.writeStr("curl: recv failed\n");
            return 1;
        }
        const chunk = recv_buf[0..@intCast(n)];
        if (!got_body) {
            if (target.findBodyStart(chunk)) |body| {
                got_body = true;
                ulib.io.writeStr(body);
            }
        } else {
            ulib.io.writeStr(chunk);
        }
    }

    if (!got_body) ulib.io.writeStr("\n");
    return 0;
}

fn sendPart(fd: u32, bytes: []const u8) u8 {
    if (ulib.net.send(fd, bytes.ptr, bytes.len, 0) < 0) {
        ulib.io.writeStr("curl: send failed\n");
        return 1;
    }
    return 0;
}
