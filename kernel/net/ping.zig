const serial = @import("../arch/x86_64/serial.zig");
const icmp = @import("icmp.zig");
const ipv4 = @import("ipv4.zig");
const resolve = @import("resolve.zig");
const virtio_net = @import("../drivers/virtio_net.zig");

/// QEMU user networking defaults.
pub const guest_ip = resolve.guest_ip;
pub const gateway_ip = ipv4.Addr{ 10, 0, 2, 2 };

const ping_id: u16 = 0x4F53;
const ping_seq: u16 = 1;

pub fn runSelfTest() void {
    if (!virtio_net.isReady()) return;

    const mac = virtio_net.macAddress();
    const gw_mac = resolve.resolve(gateway_ip, mac) orelse {
        serial.writeString("ping: ARP failed\r\n");
        return;
    };
    serial.writeString("ping: ARP ok\r\n");

    var frame: [virtio_net.max_frame_size]u8 = undefined;
    const frame_len = icmp.buildEchoRequest(&frame, gw_mac, mac, guest_ip, gateway_ip, ping_id, ping_seq);
    virtio_net.sendFrame(frame[0..frame_len]) catch {
        serial.writeString("ping: TX failed\r\n");
        return;
    };

    var recv_buf: [virtio_net.max_frame_size]u8 = undefined;
    var attempt: usize = 0;
    while (attempt < 10) : (attempt += 1) {
        if (virtio_net.pollRecv(&recv_buf, 100_000)) |len| {
            if (icmp.isEchoReply(recv_buf[0..len], gateway_ip, ping_id, ping_seq)) {
                var ip_buf: [ipv4.format_len]u8 = undefined;
                const ip_str = ipv4.format(gateway_ip, &ip_buf) orelse "?";
                serial.printf("ping: {s} reply ({d} bytes)\r\n", .{ ip_str, len });
                return;
            }
        } else |_| {}
    }
    serial.writeString("ping: timeout\r\n");
}
