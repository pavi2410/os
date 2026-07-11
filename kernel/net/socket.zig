const link = @import("link.zig");
const api = @import("socket/api.zig");
const table = @import("socket/table.zig");
const sock_icmp = @import("socket/icmp.zig");
const sock_tcp = @import("socket/tcp.zig");
const sock_udp = @import("socket/udp.zig");

pub const AddressFamily = api.AddressFamily;
pub const SocketType = api.SocketType;
pub const IpProtocol = api.IpProtocol;

pub const SocketError = api.SocketError;
pub const SockaddrIn = api.SockaddrIn;

pub const socketErrorFromPump = api.socketErrorFromPump;
pub const putSockaddrIn = api.putSockaddrIn;

pub fn create(network: *table.Network, domain: u32, sock_type: u32, protocol: i32) SocketError!table.Handle {
    const family = api.AddressFamily.fromInt(domain) orelse return SocketError.Unsupported;
    if (family != .inet) return SocketError.Unsupported;
    if (!link.isReady()) return SocketError.NotReady;

    const kind: table.Kind = switch (api.SocketType.fromInt(sock_type) orelse return SocketError.Unsupported) {
        .dgram => switch (api.IpProtocol.fromInt(protocol) orelse .udp) {
            .icmp => .icmp,
            .udp => .udp,
            else => return SocketError.Unsupported,
        },
        .stream => switch (api.IpProtocol.fromInt(protocol) orelse .tcp) {
            .tcp => .tcp,
            else => return SocketError.Unsupported,
        },
    };

    const handle = network.create(kind) orelse return SocketError.TooManySockets;
    return handle;
}

pub fn close(network: *table.Network, handle: table.Handle) void {
    if (network.get(handle)) |sock| {
        if (sock.refs == 1) sock_tcp.close(sock);
    }
    _ = network.release(handle);
}

pub fn retain(network: *table.Network, handle: table.Handle) bool {
    return network.retain(handle);
}

pub fn bind(network: *table.Network, handle: table.Handle, addr: *const SockaddrIn) SocketError!void {
    const sock = network.get(handle) orelse return SocketError.NotFound;
    if (api.sockaddrFamily(addr) != .inet) return SocketError.Unsupported;
    const udp_sock = table.asUdp(sock) orelse return SocketError.Unsupported;
    udp_sock.local_port = @byteSwap(addr.port_be);
}

pub fn connect(network: *table.Network, handle: table.Handle, addr: *const SockaddrIn) SocketError!void {
    return sock_tcp.connect(&network.sockets, handle, addr);
}

pub fn send(network: *table.Network, handle: table.Handle, data: []const u8) SocketError!usize {
    return sock_tcp.send(&network.sockets, handle, data);
}

pub fn recv(network: *table.Network, handle: table.Handle, buf: []u8, max_spins: usize) SocketError!usize {
    return sock_tcp.recv(&network.sockets, handle, buf, max_spins);
}

pub fn sendto(
    network: *table.Network,
    handle: table.Handle,
    data: []const u8,
    dest: *const SockaddrIn,
) SocketError!usize {
    const sock = network.get(handle) orelse return SocketError.NotFound;
    if (api.sockaddrFamily(dest) != .inet) return SocketError.Unsupported;
    if (!link.isReady()) return SocketError.NotReady;

    return switch (sock.active) {
        .udp => try sock_udp.send(&network.sockets, handle, data, dest),
        .icmp => try sock_icmp.send(&network.sockets, handle, dest),
        .tcp => SocketError.Unsupported,
    };
}

pub fn recvfrom(
    network: *table.Network,
    handle: table.Handle,
    buf: []u8,
    src_out: ?*SockaddrIn,
    max_spins: usize,
) SocketError!usize {
    const sock = network.get(handle) orelse return SocketError.NotFound;
    if (!link.isReady()) return SocketError.NotReady;

    return switch (sock.active) {
        .udp => try sock_udp.recv(&network.sockets, handle, buf, src_out, max_spins),
        .icmp => try sock_icmp.recv(&network.sockets, handle, buf, src_out, max_spins),
        .tcp => SocketError.Unsupported,
    };
}
