const pump = @import("../pump.zig");
const ipv4_addr = @import("common/ipv4_addr");
const abi_net = @import("abi_net");

pub const AddressFamily = abi_net.AddressFamily;
pub const SocketType = abi_net.SocketType;
pub const IpProtocol = abi_net.IpProtocol;

pub const SocketError = error{
    TooManySockets,
    Unsupported,
    NotBound,
    NotFound,
    NotConnected,
    NotReady,
    IoError,
    Timeout,
};

pub const SockaddrIn = abi_net.SockaddrIn;

pub fn socketErrorFromPump(err: pump.Error) SocketError {
    return switch (err) {
        pump.Error.IoError => SocketError.IoError,
        pump.Error.Timeout => SocketError.Timeout,
    };
}

pub fn sockaddrFamily(addr: *const SockaddrIn) ?AddressFamily {
    return AddressFamily.fromInt(addr.family);
}

pub fn putSockaddrIn(out: *SockaddrIn, ip: ipv4_addr.Addr, port_host: u16) void {
    out.* = abi_net.sockaddrIn(ip.octets, port_host);
}
