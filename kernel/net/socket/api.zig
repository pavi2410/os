const pump = @import("../pump.zig");
const ipv4_addr = @import("common/ipv4_addr");
const abi_net = @import("abi_net");

pub const AddressFamily = enum(u16) {
    inet = abi_net.AF_INET,

    pub inline fn fromInt(n: u32) ?AddressFamily {
        return switch (n) {
            @intFromEnum(AddressFamily.inet) => .inet,
            else => null,
        };
    }
};

pub const SocketType = enum(u16) {
    stream = abi_net.SOCK_STREAM,
    dgram = abi_net.SOCK_DGRAM,

    pub inline fn fromInt(n: u32) ?SocketType {
        return switch (n) {
            @intFromEnum(SocketType.stream) => .stream,
            @intFromEnum(SocketType.dgram) => .dgram,
            else => null,
        };
    }
};

pub const IpProtocol = enum(i32) {
    icmp = abi_net.IPPROTO_ICMP,
    tcp = abi_net.IPPROTO_TCP,
    udp = abi_net.IPPROTO_UDP,

    pub inline fn fromInt(n: i32) ?IpProtocol {
        return switch (n) {
            @intFromEnum(IpProtocol.icmp) => .icmp,
            @intFromEnum(IpProtocol.tcp) => .tcp,
            @intFromEnum(IpProtocol.udp) => .udp,
            else => null,
        };
    }
};

comptime {
    if (@intFromEnum(AddressFamily.inet) != abi_net.AF_INET) @compileError("AddressFamily.inet must match ABI");
    if (@intFromEnum(SocketType.stream) != abi_net.SOCK_STREAM) @compileError("SocketType.stream must match ABI");
    if (@intFromEnum(SocketType.dgram) != abi_net.SOCK_DGRAM) @compileError("SocketType.dgram must match ABI");
    if (@intFromEnum(IpProtocol.icmp) != abi_net.IPPROTO_ICMP) @compileError("IpProtocol.icmp must match ABI");
    if (@intFromEnum(IpProtocol.tcp) != abi_net.IPPROTO_TCP) @compileError("IpProtocol.tcp must match ABI");
    if (@intFromEnum(IpProtocol.udp) != abi_net.IPPROTO_UDP) @compileError("IpProtocol.udp must match ABI");
}

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
