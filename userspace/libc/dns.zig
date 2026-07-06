const libc = @import("syscall.zig");
const dns_codec = @import("dns_codec");

const default_dns = [4]u8{ 10, 0, 2, 3 };
const dns_port: u16 = 53;

/// Resolve @p name to an IPv4 address via DNS A record. Returns true on success.
pub noinline fn resolveA(name: []const u8, server: ?[4]u8, out: *[4]u8) bool {
    var dns_addr = default_dns;
    if (server) |s| dns_addr = s;

    var query: [256]u8 = undefined;
    const query_len = dns_codec.buildQuery(name, &query) catch return false;

    const fd = libc.socket(libc.AF_INET, libc.SOCK_DGRAM, 0);
    if (fd < 0) return false;

    var dest: libc.SockaddrIn = .{
        .family = libc.AF_INET,
        .port_be = @byteSwap(dns_port),
        .addr = dns_addr,
    };

    if (libc.sendto(
        @intCast(fd),
        &query,
        query_len,
        0,
        &dest,
        @sizeOf(libc.SockaddrIn),
    ) < 0) return false;

    var reply: [512]u8 = undefined;
    const n = libc.recvfrom(
        @intCast(fd),
        &reply,
        reply.len,
        0,
        null,
        null,
    );
    if (n < 12) return false;

    return dns_codec.parseFirstA(reply[0..@intCast(n)], out);
}
