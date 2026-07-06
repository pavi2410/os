const config = @import("config.zig");
const icmp = @import("icmp.zig");
const ipv4 = @import("ipv4.zig");
const link = @import("link.zig");
const resolve = @import("resolve.zig");
const udp = @import("udp.zig");

pub const AF_INET: u16 = 2;
pub const SOCK_DGRAM: u16 = 2;

pub const IPPROTO_ICMP: i32 = 1;
pub const IPPROTO_UDP: i32 = 17;

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

const Kind = enum {
    udp,
    icmp,
};

const Socket = struct {
    in_use: bool = false,
    kind: Kind = .udp,
    local_port: u16 = 0,
    icmp_id: u16 = 0,
    icmp_seq: u16 = 0,
    last_peer: ipv4.Addr = .{ 0, 0, 0, 0 },
};

const max_sockets = 16;
const ephemeral_port_min: u16 = 49152;

var sockets: [max_sockets]Socket = [_]Socket{.{}} ** max_sockets;
var next_ephemeral: u16 = ephemeral_port_min;
var next_icmp_id: u16 = 0x4000;

pub fn create(domain: u32, sock_type: u32, protocol: i32) SocketError!u32 {
    if (domain != AF_INET or sock_type != SOCK_DGRAM) return SocketError.Unsupported;
    if (!link.isReady()) return SocketError.NotReady;

    const kind: Kind = switch (protocol) {
        IPPROTO_ICMP => .icmp,
        0, IPPROTO_UDP => .udp,
        else => return SocketError.Unsupported,
    };

    var i: usize = 0;
    while (i < max_sockets) : (i += 1) {
        if (!sockets[i].in_use) {
            sockets[i] = switch (kind) {
                .udp => .{ .in_use = true, .kind = .udp },
                .icmp => .{
                    .in_use = true,
                    .kind = .icmp,
                    .icmp_id = blk: {
                        const id = next_icmp_id;
                        next_icmp_id +%= 1;
                        break :blk id;
                    },
                },
            };
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
    if (sockets[handle].kind != .udp) return SocketError.Unsupported;
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

    return switch (sockets[handle].kind) {
        .udp => try sendUdp(handle, data, dest),
        .icmp => try sendIcmp(handle, dest),
    };
}

fn sendUdp(handle: u32, data: []const u8, dest: *const SockaddrIn) SocketError!usize {
    const sock = &sockets[handle];
    if (sock.local_port == 0) {
        sock.local_port = next_ephemeral;
        next_ephemeral +%= 1;
        if (next_ephemeral < 1024) next_ephemeral = ephemeral_port_min;
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

fn sendIcmp(handle: u32, dest: *const SockaddrIn) SocketError!usize {
    const sock = &sockets[handle];
    const dst_ip = dest.addr;
    const mac = link.localMac();
    const dst_mac = resolve.resolve(dst_ip, mac) orelse return SocketError.IoError;

    const sequence = sock.icmp_seq;
    sock.icmp_seq +%= 1;
    sock.last_peer = dst_ip;

    var frame: [link.max_frame_len]u8 = undefined;
    const frame_len = icmp.buildEchoRequest(
        &frame,
        dst_mac,
        mac,
        config.guest_ip,
        dst_ip,
        sock.icmp_id,
        sequence,
    );
    link.transmitOrFail(frame[0..frame_len]) catch return SocketError.IoError;
    return icmp.echo_payload_len;
}

pub fn recvfrom(
    handle: u32,
    buf: []u8,
    src_out: ?*SockaddrIn,
    max_spins: usize,
) SocketError!usize {
    if (handle >= max_sockets or !sockets[handle].in_use) return SocketError.NotFound;
    if (!link.isReady()) return SocketError.NotReady;

    return switch (sockets[handle].kind) {
        .udp => try recvUdp(handle, buf, src_out, max_spins),
        .icmp => try recvIcmp(handle, buf, src_out, max_spins),
    };
}

fn recvUdp(
    handle: u32,
    buf: []u8,
    src_out: ?*SockaddrIn,
    max_spins: usize,
) SocketError!usize {
    const local_port = sockets[handle].local_port;
    if (local_port == 0) return SocketError.NotBound;

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

fn recvIcmp(
    handle: u32,
    buf: []u8,
    src_out: ?*SockaddrIn,
    max_spins: usize,
) SocketError!usize {
    const sock = &sockets[handle];
    const expect_seq = if (sock.icmp_seq > 0) sock.icmp_seq - 1 else 0;

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
        const payload = icmp.matchEchoReply(recv_buf[0..len], sock.icmp_id, expect_seq, &src_ip) orelse continue;
        if (!ipv4.equal(src_ip, sock.last_peer)) continue;

        const copy_len = @min(payload.len, buf.len);
        @memcpy(buf[0..copy_len], payload[0..copy_len]);
        if (src_out) |out| {
            out.* = .{
                .family = AF_INET,
                .port_be = 0,
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
