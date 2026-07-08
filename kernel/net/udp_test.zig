const config = @import("config.zig");
const ipv4_addr = @import("common_ipv4_addr");
const link = @import("link.zig");
const resolve = @import("resolve.zig");
const udp = @import("udp.zig");

pub const dns_port: u16 = 53;

const test_src_port: u16 = 42000;

pub fn dnsReplyOk() bool {
    if (!link.isReady()) return false;

    const mac = link.localMac();
    const dns_mac = resolve.resolve(config.dns_ip, mac) orelse return false;

    var query: [32]u8 = undefined;
    const query_len = buildExampleQuery(&query);

    var frame: [link.max_frame_len]u8 = undefined;
    const frame_len = udp.build(
        &frame,
        dns_mac,
        mac,
        config.guest_ip,
        config.dns_ip,
        test_src_port,
        dns_port,
        query[0..query_len],
    );
    link.transmitOrFail(frame[0..frame_len]) catch return false;

    var recv_buf: [link.max_frame_len]u8 = undefined;
    var attempt: usize = 0;
    while (attempt < 10) : (attempt += 1) {
        if (link.pollReceive(&recv_buf, 100_000)) |len| {
            var src_ip: ipv4_addr.Addr = undefined;
            var src_port: u16 = 0;
            if (udp.match(recv_buf[0..len], test_src_port, &src_ip, &src_port)) |payload| {
                if (src_ip.eql(config.dns_ip) and src_port == dns_port and payload.len >= 12) {
                    return true;
                }
            }
        }
    }
    return false;
}

fn buildExampleQuery(out: []u8) usize {
    // DNS query for example.com, type A.
    @memset(out[0..32], 0);
    out[0] = 0xAA;
    out[1] = 0xAA; // transaction id
    out[2] = 0x01;
    out[3] = 0x00; // standard query
    out[4] = 0x00;
    out[5] = 0x01; // 1 question
    const name = [_]u8{ 7, 'e', 'x', 'a', 'm', 'p', 'l', 'e', 3, 'c', 'o', 'm', 0 };
    @memcpy(out[12..][0..name.len], &name);
    const tail_off = 12 + name.len;
    out[tail_off] = 0x00;
    out[tail_off + 1] = 0x01; // A
    out[tail_off + 2] = 0x00;
    out[tail_off + 3] = 0x01; // IN
    return tail_off + 4;
}
