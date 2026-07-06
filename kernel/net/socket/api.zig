const pump = @import("../pump.zig");
const ipv4 = @import("../ipv4.zig");
const abi_net = @import("abi_net");

pub const AF_INET = abi_net.AF_INET;
pub const SOCK_DGRAM = abi_net.SOCK_DGRAM;
pub const SOCK_STREAM = abi_net.SOCK_STREAM;

pub const IPPROTO_ICMP = abi_net.IPPROTO_ICMP;
pub const IPPROTO_TCP = abi_net.IPPROTO_TCP;
pub const IPPROTO_UDP = abi_net.IPPROTO_UDP;

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

pub fn putSockaddrIn(out: *SockaddrIn, ip: ipv4.Addr, port_host: u16) void {
    out.* = abi_net.sockaddrIn(ip, port_host);
}
