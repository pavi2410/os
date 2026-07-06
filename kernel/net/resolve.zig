const arp = @import("arp.zig");
const ipv4 = @import("ipv4.zig");
const virtio_net = @import("../drivers/virtio_net.zig");

pub const guest_ip = ipv4.Addr{ 10, 0, 2, 15 };

var cached_mac: ?[virtio_net.mac_len]u8 = null;
var cached_ip: ipv4.Addr = .{ 0, 0, 0, 0 };

pub fn resolve(ip: ipv4.Addr, src_mac: [virtio_net.mac_len]u8) ?[virtio_net.mac_len]u8 {
    if (cached_mac) |mac| {
        if (ipv4.equal(cached_ip, ip)) return mac;
    }

    var frame: [virtio_net.max_frame_size]u8 = undefined;
    const frame_len = arp.buildRequest(&frame, src_mac, guest_ip, ip);
    virtio_net.sendFrame(frame[0..frame_len]) catch return null;

    var recv_buf: [virtio_net.max_frame_size]u8 = undefined;
    var attempt: usize = 0;
    while (attempt < 5) : (attempt += 1) {
        if (virtio_net.pollRecv(&recv_buf, 100_000)) |len| {
            if (arp.senderMacFor(recv_buf[0..len], ip)) |resolved| {
                cached_mac = resolved;
                cached_ip = ip;
                return resolved;
            }
        } else |_| {}
    }
    return null;
}

pub fn resetCache() void {
    cached_mac = null;
    cached_ip = .{ 0, 0, 0, 0 };
}
