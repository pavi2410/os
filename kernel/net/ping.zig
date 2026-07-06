const serial = @import("../arch/x86_64/serial.zig");
const config = @import("config.zig");
const icmp = @import("icmp.zig");
const ipv4 = @import("ipv4.zig");
const link = @import("link.zig");
const resolve = @import("resolve.zig");

const ping_id: u16 = 0x4F53;
const ping_seq: u16 = 1;

pub fn runSelfTest() void {
    if (!link.isReady()) return;

    const mac = link.localMac();
    const gw_mac = resolve.resolve(config.gateway_ip, mac) orelse {
        serial.writeString("ping: ARP failed\r\n");
        return;
    };
    serial.writeString("ping: ARP ok\r\n");

    var frame: [link.max_frame_len]u8 = undefined;
    const frame_len = icmp.buildEchoRequest(&frame, gw_mac, mac, config.guest_ip, config.gateway_ip, ping_id, ping_seq);
    link.transmitOrFail(frame[0..frame_len]) catch {
        serial.writeString("ping: TX failed\r\n");
        return;
    };

    var recv_buf: [link.max_frame_len]u8 = undefined;
    var attempt: usize = 0;
    while (attempt < 10) : (attempt += 1) {
        if (link.pollReceive(&recv_buf, 100_000)) |len| {
            if (icmp.isEchoReply(recv_buf[0..len], config.gateway_ip, ping_id, ping_seq)) {
                var ip_buf: [ipv4.format_len]u8 = undefined;
                const ip_str = ipv4.format(config.gateway_ip, &ip_buf) orelse "?";
                serial.printf("ping: {s} reply ({d} bytes)\r\n", .{ ip_str, len });
                return;
            }
        }
    }
    serial.writeString("ping: timeout\r\n");
}
