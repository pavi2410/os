const dns_codec = @import("dns_codec");
const net = @import("net.zig");

const default_dns = [4]u8{ 10, 0, 2, 3 };
const dns_port: u16 = 53;

/// Resolve @p name to an IPv4 address via DNS A record. Returns true on success.
pub noinline fn resolveA(name: []const u8, server: ?[4]u8, out: *[4]u8) bool {
    var dns_addr = default_dns;
    if (server) |s| dns_addr = s;

    var query: [256]u8 = undefined;
    const query_len = dns_codec.buildQuery(name, &query) catch return false;

    const fd = net.socket(.inet, .dgram, null);
    if (fd < 0) return false;

    var dest = net.sockaddrIn(dns_addr, dns_port);

    if (net.sendto(
        @intCast(fd),
        &query,
        query_len,
        0,
        &dest,
    ) < 0) return false;

    var reply: [512]u8 = undefined;
    const n = net.recvfrom(
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
