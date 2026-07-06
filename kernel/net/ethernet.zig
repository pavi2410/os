pub const mac_len = 6;
pub const header_len = 14;
pub const min_frame_len = 60;
pub const max_frame_len = 1518;

pub const broadcast_mac = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };

pub const ethertype_arp: u16 = 0x0806;
pub const ethertype_ipv4: u16 = 0x0800;

pub const Header = extern struct {
    dst: [mac_len]u8,
    src: [mac_len]u8,
    ethertype_be: u16,
};

pub fn ethertypeHost(hdr: *const Header) u16 {
    return @byteSwap(hdr.ethertype_be);
}

pub fn putHeader(buf: []u8, dst_mac: [mac_len]u8, src_mac: [mac_len]u8, ethertype: u16) void {
    @memcpy(buf[0..mac_len], &dst_mac);
    @memcpy(buf[mac_len..][0..mac_len], &src_mac);
    buf[12] = @truncate(ethertype >> 8);
    buf[13] = @truncate(ethertype);
}
