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

pub fn create(domain: u32, sock_type: u32, protocol: i32) SocketError!u32 {
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

    const handle = table.create(kind) orelse return SocketError.TooManySockets;
    return handle;
}

pub fn close(handle: u32) void {
    if (table.get(handle)) |sock| {
        sock_tcp.close(sock);
    }
    table.release(handle);
}

pub fn bind(handle: u32, addr: *const SockaddrIn) SocketError!void {
    const sock = table.get(handle) orelse return SocketError.NotFound;
    if (api.sockaddrFamily(addr) != .inet) return SocketError.Unsupported;
    const udp_sock = table.asUdp(sock) orelse return SocketError.Unsupported;
    udp_sock.local_port = @byteSwap(addr.port_be);
}

pub fn connect(handle: u32, addr: *const SockaddrIn) SocketError!void {
    return sock_tcp.connect(handle, addr);
}

pub fn send(handle: u32, data: []const u8) SocketError!usize {
    return sock_tcp.send(handle, data);
}

pub fn recv(handle: u32, buf: []u8, max_spins: usize) SocketError!usize {
    return sock_tcp.recv(handle, buf, max_spins);
}

pub fn sendto(
    handle: u32,
    data: []const u8,
    dest: *const SockaddrIn,
) SocketError!usize {
    const sock = table.get(handle) orelse return SocketError.NotFound;
    if (api.sockaddrFamily(dest) != .inet) return SocketError.Unsupported;
    if (!link.isReady()) return SocketError.NotReady;

    return switch (sock.active) {
        .udp => try sock_udp.send(handle, data, dest),
        .icmp => try sock_icmp.send(handle, dest),
        .tcp => SocketError.Unsupported,
    };
}

pub fn recvfrom(
    handle: u32,
    buf: []u8,
    src_out: ?*SockaddrIn,
    max_spins: usize,
) SocketError!usize {
    const sock = table.get(handle) orelse return SocketError.NotFound;
    if (!link.isReady()) return SocketError.NotReady;

    return switch (sock.active) {
        .udp => try sock_udp.recv(handle, buf, src_out, max_spins),
        .icmp => try sock_icmp.recv(handle, buf, src_out, max_spins),
        .tcp => SocketError.Unsupported,
    };
}
