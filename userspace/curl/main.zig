const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;

const ulib = @import("ulib");
const target = @import("target.zig");

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
        ulib.process.exit(1);
    }

    const arg = ulib.io.cstr(argv[1]);
    const parsed = target.parse(arg, &norm_buf, &host_buf, &path_buf) catch {
        writeStr("curl: bad url\n");
        ulib.process.exit(1);
    };

    var port = parsed.port;
    if (argc >= 3) {
        port = ulib.parse.parsePort(ulib.io.cstr(argv[2])) orelse {
            writeStr("curl: bad port\n");
            ulib.process.exit(1);
        };
    }

    var host_ip: [4]u8 = undefined;
    if (ulib.ip.parseIpv4(parsed.host, &host_ip)) {
        // literal IPv4
    } else if (!resolveName(parsed.host, &host_ip)) {
        writeStr("curl: could not resolve host\n");
        ulib.process.exit(1);
    }

    httpGet(parsed.host, &host_ip, port, parsed.path);
}

noinline fn resolveName(name: []const u8, out: *[4]u8) bool {
    return ulib.dns.resolveA(name, null, out);
}

noinline fn httpGet(host: []const u8, ip: *const [4]u8, port: u16, path: []const u8) void {
    const fd = ulib.net.socket(
        ulib.net.AF_INET,
        ulib.net.SOCK_STREAM,
        ulib.net.IPPROTO_TCP,
    );
    if (fd < 0) {
        writeStr("curl: socket failed\n");
        ulib.process.exit(1);
    }

    var dest = ulib.net.sockaddrIn(ip.*, port);

    if (ulib.net.connect(@intCast(fd), &dest) < 0) {
        writeStr("curl: connect failed\n");
        ulib.process.exit(1);
    }

    var request: [256]u8 = undefined;
    const request_len = target.buildRequest(host, path, &request) orelse {
        writeStr("curl: request too large\n");
        ulib.process.exit(1);
    };
    sendPart(@intCast(fd), request[0..request_len]);

    var got_body = false;
    while (true) {
        const n = ulib.net.recv(@intCast(fd), &recv_buf, recv_buf.len, 0);
        if (n == 0) break;
        if (n < 0) {
            writeStr("curl: recv failed\n");
            ulib.process.exit(1);
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
    ulib.process.exit(0);
}

fn sendPart(fd: u32, bytes: []const u8) void {
    if (ulib.net.send(fd, bytes.ptr, bytes.len, 0) < 0) {
        writeStr("curl: send failed\n");
        ulib.process.exit(1);
    }
}

fn writeStr(s: []const u8) void {
    ulib.io.writeStr(s);
}
