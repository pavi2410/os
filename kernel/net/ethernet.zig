pub const mac_len = 6;
pub const header_len = 14;
pub const min_frame_len = 60;
pub const max_frame_len = 1518;

pub const Mac = [mac_len]u8;

pub const broadcast: Mac = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };

/// Buffer size for `format` (`aa:bb:cc:dd:ee:ff`).
pub const format_len = 17;

pub const ethertype_arp: u16 = 0x0806;
pub const ethertype_ipv4: u16 = 0x0800;

pub const Header = extern struct {
    dst: Mac,
    src: Mac,
    ethertype_be: u16,
};

pub fn equal(a: Mac, b: Mac) bool {
    return @as(u48, @bitCast(a)) == @as(u48, @bitCast(b));
}

/// Writes lowercase hex with colon separators into `buf`. Returns slice or null.
pub fn format(mac: Mac, buf: []u8) ?[]const u8 {
    if (buf.len < format_len) return null;
    var i: usize = 0;
    var byte_idx: usize = 0;
    while (byte_idx < mac_len) : (byte_idx += 1) {
        if (byte_idx > 0) {
            buf[i] = ':';
            i += 1;
        }
        const b = mac[byte_idx];
        buf[i] = hexDigit(b >> 4);
        buf[i + 1] = hexDigit(b & 0xF);
        i += 2;
    }
    return buf[0..format_len];
}

fn hexDigit(nibble: u8) u8 {
    const v = nibble & 0xF;
    return if (v < 10) '0' + v else 'a' + (v - 10);
}

pub fn ethertypeHost(hdr: *const Header) u16 {
    return @byteSwap(hdr.ethertype_be);
}

pub fn putHeader(buf: []u8, dst_mac: Mac, src_mac: Mac, ethertype: u16) void {
    @memcpy(buf[0..mac_len], &dst_mac);
    @memcpy(buf[mac_len..][0..mac_len], &src_mac);
    buf[12] = @truncate(ethertype >> 8);
    buf[13] = @truncate(ethertype);
}
