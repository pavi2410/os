const config = @import("config.zig");
const ipv4 = @import("ipv4.zig");
const link = @import("link.zig");
const resolve = @import("resolve.zig");
const udp = @import("udp.zig");

pub const AF_INET: u16 = 2;
pub const SOCK_DGRAM: u16 = 2;

pub const SocketError = error{
    TooManySockets,
    Unsupported,
    NotBound,
    NotFound,
    NotReady,
    IoError,
    Timeout,
};

pub const SockaddrIn = extern struct {
    family: u16,
    port_be: u16,
    addr: ipv4.Addr,
    zero: [8]u8,
};

const max_sockets = 16;

const Socket = struct {
    in_use: bool = false,
    local_port: u16 = 0,
};

var sockets: [max_sockets]Socket = [_]Socket{.{}} ** max_sockets;
var next_ephemeral: u16 = 49152;

pub fn create(domain: u32, sock_type: u32, protocol: i32) SocketError!u32 {
    if (domain != AF_INET or sock_type != SOCK_DGRAM) return SocketError.Unsupported;
    _ = protocol;
    if (!link.isReady()) return SocketError.NotReady;

    var i: usize = 0;
    while (i < max_sockets) : (i += 1) {
        if (!sockets[i].in_use) {
            sockets[i] = .{ .in_use = true, .local_port = 0 };
            return @intCast(i);
        }
    }
    return SocketError.TooManySockets;
}

pub fn close(handle: u32) void {
    if (handle >= max_sockets) return;
    sockets[handle] = .{};
}

pub fn bind(handle: u32, addr: *const SockaddrIn) SocketError!void {
    if (handle >= max_sockets or !sockets[handle].in_use) return SocketError.NotFound;
    if (addr.family != AF_INET) return SocketError.Unsupported;
    sockets[handle].local_port = @byteSwap(addr.port_be);
}

pub fn sendto(
    handle: u32,
    data: []const u8,
    dest: *const SockaddrIn,
) SocketError!usize {
    if (handle >= max_sockets or !sockets[handle].in_use) return SocketError.NotFound;
    if (dest.family != AF_INET) return SocketError.Unsupported;
    if (!link.isReady()) return SocketError.NotReady;

    const sock = &sockets[handle];
    if (sock.local_port == 0) {
        sock.local_port = next_ephemeral;
        next_ephemeral +%= 1;
        if (next_ephemeral < 1024) next_ephemeral = 49152;
    }

    const dst_ip = dest.addr;
    const dst_port = @byteSwap(dest.port_be);
    const mac = link.localMac();
    const dst_mac = resolve.resolve(dst_ip, mac) orelse return SocketError.IoError;

    var frame: [link.max_frame_len]u8 = undefined;
    const frame_len = udp.build(
        &frame,
        dst_mac,
        mac,
        config.guest_ip,
        dst_ip,
        sock.local_port,
        dst_port,
        data,
    );
    link.transmitOrFail(frame[0..frame_len]) catch return SocketError.IoError;
    return data.len;
}

pub fn recvfrom(
    handle: u32,
    buf: []u8,
    src_out: ?*SockaddrIn,
    max_spins: usize,
) SocketError!usize {
    if (handle >= max_sockets or !sockets[handle].in_use) return SocketError.NotFound;
    const local_port = sockets[handle].local_port;
    if (local_port == 0) return SocketError.NotBound;
    if (!link.isReady()) return SocketError.NotReady;

    var recv_buf: [link.max_frame_len]u8 = undefined;
    var spins: usize = 0;
    while (spins < max_spins) : (spins += 1) {
        const len = link.receive(&recv_buf) catch |err| switch (err) {
            error.NoPacket => {
                asm volatile ("sti; pause; cli" ::: .{ .memory = true });
                continue;
            },
            else => return SocketError.IoError,
        };

        var src_ip: ipv4.Addr = undefined;
        var src_port: u16 = 0;
        const payload = udp.match(recv_buf[0..len], local_port, &src_ip, &src_port) orelse continue;
        const copy_len = @min(payload.len, buf.len);
        @memcpy(buf[0..copy_len], payload[0..copy_len]);
        if (src_out) |out| {
            out.* = .{
                .family = AF_INET,
                .port_be = @byteSwap(src_port),
                .addr = src_ip,
                .zero = .{0} ** 8,
            };
        }
        return copy_len;
    }
    return SocketError.Timeout;
}

pub fn putSockaddrIn(out: *SockaddrIn, ip: ipv4.Addr, port_host: u16) void {
    out.* = .{
        .family = AF_INET,
        .port_be = @byteSwap(port_host),
        .addr = ip,
        .zero = .{0} ** 8,
    };
}
