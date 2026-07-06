const config = @import("config.zig");
const ethernet = @import("ethernet.zig");
const ipv4 = @import("ipv4.zig");
const link = @import("link.zig");
const resolve = @import("resolve.zig");
const abi_net = @import("abi_net");

pub const NetConfig = abi_net.NetConfig;
pub const NeighEntry = abi_net.NeighEntry;

pub fn fillConfig(out: *NetConfig) void {
    out.ip = config.guest_ip;
    out.mask = config.lan_mask;
    out.gateway = config.gateway_ip;
    out.dns = config.dns_ip;
    out.mac = link.localMac();
}

pub fn fillNeighbors(buf: []NeighEntry) usize {
    var scratch: [8]resolve.Neighbor = undefined;
    const count = resolve.listNeighbors(&scratch);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        buf[i].ip = scratch[i].ip;
        buf[i].mac = scratch[i].mac;
    }
    return count;
}
