const arp = @import("arp.zig");
const config = @import("config.zig");
const ethernet = @import("ethernet.zig");
const ipv4 = @import("ipv4.zig");
const link = @import("link.zig");

var cached_mac: ?ethernet.Mac = null;
var cached_ip: ipv4.Addr = .{ 0, 0, 0, 0 };

pub fn resolve(ip: ipv4.Addr, src_mac: ethernet.Mac) ?ethernet.Mac {
    if (cached_mac) |mac| {
        if (ipv4.equal(cached_ip, ip)) return mac;
    }

    var frame: [link.max_frame_len]u8 = undefined;
    const frame_len = arp.buildRequest(&frame, src_mac, config.guest_ip, ip);
    link.transmitOrFail(frame[0..frame_len]) catch return null;

    var recv_buf: [link.max_frame_len]u8 = undefined;
    var attempt: usize = 0;
    while (attempt < 5) : (attempt += 1) {
        if (link.pollReceive(&recv_buf, 100_000)) |len| {
            if (arp.senderMacFor(recv_buf[0..len], ip)) |resolved| {
                cached_mac = resolved;
                cached_ip = ip;
                return resolved;
            }
        }
    }
    return null;
}

pub fn resetCache() void {
    cached_mac = null;
    cached_ip = .{ 0, 0, 0, 0 };
}
