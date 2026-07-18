pub const AddressFamily = enum(u16) {
    inet = 2,

    pub fn fromInt(n: u32) ?AddressFamily {
        return switch (n) {
            @intFromEnum(AddressFamily.inet) => .inet,
            else => null,
        };
    }
};

pub const SocketType = enum(u16) {
    stream = 1,
    dgram = 2,

    pub fn fromInt(n: u32) ?SocketType {
        return switch (n) {
            @intFromEnum(SocketType.stream) => .stream,
            @intFromEnum(SocketType.dgram) => .dgram,
            else => null,
        };
    }
};

pub const IpProtocol = enum(i32) {
    icmp = 1,
    tcp = 6,
    udp = 17,

    pub fn fromInt(n: i32) ?IpProtocol {
        return switch (n) {
            @intFromEnum(IpProtocol.icmp) => .icmp,
            @intFromEnum(IpProtocol.tcp) => .tcp,
            @intFromEnum(IpProtocol.udp) => .udp,
            else => null,
        };
    }
};

pub const SockaddrIn = extern struct {
    family: u16,
    port_be: u16,
    addr: [4]u8,
    zero: [8]u8 = .{0} ** 8,
};

pub fn sockaddrIn(addr: [4]u8, port_host: u16) SockaddrIn {
    return .{
        .family = @intFromEnum(AddressFamily.inet),
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

comptime {
    if (@intFromEnum(AddressFamily.inet) != 2) @compileError("AddressFamily.inet must be 2");
    if (@intFromEnum(SocketType.stream) != 1) @compileError("SocketType.stream must be 1");
    if (@intFromEnum(SocketType.dgram) != 2) @compileError("SocketType.dgram must be 2");
    if (@intFromEnum(IpProtocol.icmp) != 1) @compileError("IpProtocol.icmp must be 1");
    if (@intFromEnum(IpProtocol.tcp) != 6) @compileError("IpProtocol.tcp must be 6");
    if (@intFromEnum(IpProtocol.udp) != 17) @compileError("IpProtocol.udp must be 17");
}
