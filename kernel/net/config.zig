const ip = @import("common_ipv4_addr");

/// QEMU user-mode networking defaults (10.0.2.0/24).
pub const guest_ip = ip.Addr.parse("10.0.2.15");
pub const gateway_ip = ip.Addr.parse("10.0.2.2");
pub const dns_ip = ip.Addr.parse("10.0.2.3");
pub const lan_mask = ip.Addr.parse("255.255.255.0");

pub fn onGuestLan(addr: ip.Addr) bool {
    return addr.sameSubnet(guest_ip, lan_mask);
}
