pub const AF_INET: u16 = 2;
pub const SOCK_STREAM: u16 = 1;
pub const SOCK_DGRAM: u16 = 2;

pub const IPPROTO_ICMP: i32 = 1;
pub const IPPROTO_TCP: i32 = 6;
pub const IPPROTO_UDP: i32 = 17;

pub const SockaddrIn = extern struct {
    family: u16,
    port_be: u16,
    addr: [4]u8,
    zero: [8]u8 = .{0} ** 8,
};

pub fn sockaddrIn(addr: [4]u8, port_host: u16) SockaddrIn {
    return .{
        .family = AF_INET,
        .port_be = @byteSwap(port_host),
        .addr = addr,
    };
}

pub const NetConfig = extern struct {
    ip: [4]u8,
    mask: [4]u8,
    gateway: [4]u8,
    dns: [4]u8,
    mac: [6]u8,
};

pub const NeighEntry = extern struct {
    ip: [4]u8,
    mac: [6]u8,
};
