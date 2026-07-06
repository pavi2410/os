const arp = @import("arp.zig");
const config = @import("config.zig");
const ethernet = @import("ethernet.zig");
const ipv4 = @import("ipv4.zig");
const link = @import("link.zig");

const cache_size = 8;

const CacheEntry = struct {
    ip: ipv4.Addr = .{ 0, 0, 0, 0 },
    mac: ethernet.Mac = undefined,
    valid: bool = false,
};

var cache: [cache_size]CacheEntry = [_]CacheEntry{.{}} ** cache_size;
var next_slot: usize = 0;

pub fn resolve(ip: ipv4.Addr, src_mac: ethernet.Mac) ?ethernet.Mac {
    for (&cache) |entry| {
        if (entry.valid and ipv4.equal(entry.ip, ip)) return entry.mac;
    }

    var frame: [link.max_frame_len]u8 = undefined;
    const frame_len = arp.buildRequest(&frame, src_mac, config.guest_ip, ip);
    link.transmitOrFail(frame[0..frame_len]) catch return null;

    var recv_buf: [link.max_frame_len]u8 = undefined;
    var attempt: usize = 0;
    while (attempt < 5) : (attempt += 1) {
        if (link.pollReceive(&recv_buf, 100_000)) |len| {
            if (arp.senderMacFor(recv_buf[0..len], ip)) |resolved| {
                store(ip, resolved);
                return resolved;
            }
        }
    }
    return null;
}

pub fn resetCache() void {
    for (&cache) |*entry| entry.* = .{};
    next_slot = 0;
}

fn store(ip: ipv4.Addr, mac: ethernet.Mac) void {
    for (&cache) |*entry| {
        if (entry.valid and ipv4.equal(entry.ip, ip)) {
            entry.mac = mac;
            return;
        }
    }

    cache[next_slot] = .{ .ip = ip, .mac = mac, .valid = true };
    next_slot = (next_slot + 1) % cache_size;
}
