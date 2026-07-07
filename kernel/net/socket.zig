const link = @import("link.zig");
const api = @import("socket/api.zig");
const table = @import("socket/table.zig");
const sock_icmp = @import("socket/icmp.zig");
const sock_tcp = @import("socket/tcp.zig");
const sock_udp = @import("socket/udp.zig");

pub const AF_INET = api.AF_INET;
pub const SOCK_DGRAM = api.SOCK_DGRAM;
pub const SOCK_STREAM = api.SOCK_STREAM;

pub const IPPROTO_ICMP = api.IPPROTO_ICMP;
pub const IPPROTO_TCP = api.IPPROTO_TCP;
pub const IPPROTO_UDP = api.IPPROTO_UDP;

pub const SocketError = api.SocketError;
pub const SockaddrIn = api.SockaddrIn;

pub const socketErrorFromPump = api.socketErrorFromPump;
pub const putSockaddrIn = api.putSockaddrIn;

pub fn create(domain: u32, sock_type: u32, protocol: i32) SocketError!u32 {
    if (domain != AF_INET) return SocketError.Unsupported;
    if (!link.isReady()) return SocketError.NotReady;

    const kind: table.Kind = switch (sock_type) {
        SOCK_DGRAM => switch (protocol) {
            IPPROTO_ICMP => .icmp,
            0, IPPROTO_UDP => .udp,
            else => return SocketError.Unsupported,
        },
        SOCK_STREAM => switch (protocol) {
            0, IPPROTO_TCP => .tcp,
            else => return SocketError.Unsupported,
        },
        else => return SocketError.Unsupported,
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
    if (addr.family != AF_INET) return SocketError.Unsupported;
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
    if (dest.family != AF_INET) return SocketError.Unsupported;
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
