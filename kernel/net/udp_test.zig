const serial = @import("../arch/x86_64/serial.zig");
const ipv4 = @import("ipv4.zig");
const resolve = @import("resolve.zig");
const udp = @import("udp.zig");
const virtio_net = @import("../drivers/virtio_net.zig");

/// QEMU user networking DNS forwarder.
pub const dns_ip = ipv4.Addr{ 10, 0, 2, 3 };
pub const dns_port: u16 = 53;

pub fn runSelfTest() void {
    if (!virtio_net.isReady()) return;

    const mac = virtio_net.macAddress();
    const dns_mac = resolve.resolve(dns_ip, mac) orelse {
        serial.writeString("udp: ARP failed\r\n");
        return;
    };

    var query: [32]u8 = undefined;
    const query_len = buildExampleQuery(&query);

    var frame: [virtio_net.max_frame_size]u8 = undefined;
    const frame_len = udp.build(
        &frame,
        dns_mac,
        mac,
        resolve.guest_ip,
        dns_ip,
        42000,
        dns_port,
        query[0..query_len],
    );
    virtio_net.sendFrame(frame[0..frame_len]) catch {
        serial.writeString("udp: TX failed\r\n");
        return;
    };

    var recv_buf: [virtio_net.max_frame_size]u8 = undefined;
    var attempt: usize = 0;
    while (attempt < 10) : (attempt += 1) {
        if (virtio_net.pollRecv(&recv_buf, 100_000)) |len| {
            var src_ip: ipv4.Addr = undefined;
            var src_port: u16 = 0;
            if (udp.match(recv_buf[0..len], 42000, &src_ip, &src_port)) |payload| {
                if (ipv4.equal(src_ip, dns_ip) and src_port == dns_port and payload.len >= 12) {
                    serial.printf("udp: DNS reply ({d} bytes)\r\n", .{payload.len});
                    return;
                }
            }
        } else |_| {}
    }
    serial.writeString("udp: timeout\r\n");
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
