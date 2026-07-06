const config = @import("config.zig");
const icmp = @import("icmp.zig");
const ipv4 = @import("ipv4.zig");
const link = @import("link.zig");
const pump = @import("pump.zig");
const resolve = @import("resolve.zig");
const tcp = @import("tcp.zig");
const udp = @import("udp.zig");
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

fn socketErrorFromPump(err: pump.Error) SocketError {
    return switch (err) {
        pump.Error.IoError => SocketError.IoError,
        pump.Error.Timeout => SocketError.Timeout,
    };
}

const Kind = enum {
    udp,
    icmp,
    tcp,
};

const TcpState = enum {
    closed,
    syn_sent,
    established,
    peer_closed,
};

const rx_buf_size = 8192;

const Socket = struct {
    in_use: bool = false,
    kind: Kind = .udp,
    local_port: u16 = 0,
    icmp_id: u16 = 0,
    icmp_seq: u16 = 0,
    last_peer: ipv4.Addr = .{ 0, 0, 0, 0 },
    tcp_state: TcpState = .closed,
    remote_ip: ipv4.Addr = .{ 0, 0, 0, 0 },
    remote_port: u16 = 0,
    snd_isn: u32 = 0,
    snd_nxt: u32 = 0,
    rcv_nxt: u32 = 0,
    rx_buf: [rx_buf_size]u8 = undefined,
    rx_len: usize = 0,
};

const max_sockets = 16;
const ephemeral_port_min: u16 = 49152;
const max_tcp_segment = 1400;
const connect_spins: usize = 500_000;
const send_spins: usize = 500_000;

var sockets: [max_sockets]Socket = [_]Socket{.{}} ** max_sockets;
var next_ephemeral: u16 = ephemeral_port_min;
var next_icmp_id: u16 = 0x4000;
var next_isn: u32 = 0x12340000;
var tcp_rx_scratch: [link.max_frame_len]u8 = undefined;
var tcp_tx_frame: [link.max_frame_len]u8 = undefined;

pub fn create(domain: u32, sock_type: u32, protocol: i32) SocketError!u32 {
    if (domain != AF_INET) return SocketError.Unsupported;
    if (!link.isReady()) return SocketError.NotReady;

    const kind: Kind = switch (sock_type) {
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
                .tcp => .{ .in_use = true, .kind = .tcp },
            };
            return @intCast(i);
        }
    }
    return SocketError.TooManySockets;
}

pub fn close(handle: u32) void {
    if (handle >= max_sockets) return;
    const sock = &sockets[handle];
    if (sock.in_use and sock.kind == .tcp and sock.tcp_state == .established) {
        tcpSendSegment(sock, sock.snd_nxt, sock.rcv_nxt, tcp.flag_fin | tcp.flag_ack, "") catch {};
    }
    sockets[handle] = .{};
}

pub fn bind(handle: u32, addr: *const SockaddrIn) SocketError!void {
    if (handle >= max_sockets or !sockets[handle].in_use) return SocketError.NotFound;
    if (addr.family != AF_INET) return SocketError.Unsupported;
    if (sockets[handle].kind != .udp) return SocketError.Unsupported;
    sockets[handle].local_port = @byteSwap(addr.port_be);
}

pub fn connect(handle: u32, addr: *const SockaddrIn) SocketError!void {
    if (handle >= max_sockets or !sockets[handle].in_use) return SocketError.NotFound;
    const sock = &sockets[handle];
    if (sock.kind != .tcp) return SocketError.Unsupported;
    if (addr.family != AF_INET) return SocketError.Unsupported;
    if (!link.isReady()) return SocketError.NotReady;
    if (sock.tcp_state != .closed) return SocketError.IoError;

    sock.remote_ip = addr.addr;
    sock.remote_port = @byteSwap(addr.port_be);
    sock.local_port = next_ephemeral;
    next_ephemeral +%= 1;
    if (next_ephemeral < 1024) next_ephemeral = ephemeral_port_min;

    sock.snd_isn = next_isn;
    next_isn +%= 65536;

    try tcpSendSegment(sock, sock.snd_isn, 0, tcp.flag_syn, "");
    sock.tcp_state = .syn_sent;

    const seg = (try pollTcpSegment(sock, connect_spins)) orelse return SocketError.Timeout;

    if (seg.flags & (tcp.flag_syn | tcp.flag_ack) != (tcp.flag_syn | tcp.flag_ack)) return SocketError.IoError;
    if (seg.ack != sock.snd_isn + 1) return SocketError.IoError;

    sock.rcv_nxt = seg.seq + 1;
    sock.snd_nxt = sock.snd_isn + 1;
    try tcpSendSegment(sock, sock.snd_nxt, sock.rcv_nxt, tcp.flag_ack, "");
    sock.tcp_state = .established;
}

pub fn send(handle: u32, data: []const u8) SocketError!usize {
    if (handle >= max_sockets or !sockets[handle].in_use) return SocketError.NotFound;
    const sock = &sockets[handle];
    if (sock.kind != .tcp) return SocketError.Unsupported;
    if (sock.tcp_state != .established) return SocketError.NotConnected;
    if (!link.isReady()) return SocketError.NotReady;

    const chunk = @min(data.len, max_tcp_segment);
    try tcpSendSegment(sock, sock.snd_nxt, sock.rcv_nxt, tcp.flag_ack | tcp.flag_psh, data[0..chunk]);
    const expect_ack = sock.snd_nxt + @as(u32, @intCast(chunk));
    sock.snd_nxt = expect_ack;

    var spins: usize = 0;
    while (spins < send_spins) : (spins += 1) {
        const seg = pollTcpSegment(sock, 1) catch return SocketError.IoError;
        if (seg) |s| {
            try ingestTcpSegment(sock, s);
            if (s.flags & tcp.flag_ack != 0 and s.ack >= expect_ack) return chunk;
        }
    }
    return SocketError.Timeout;
}

pub fn recv(handle: u32, buf: []u8, max_spins: usize) SocketError!usize {
    if (handle >= max_sockets or !sockets[handle].in_use) return SocketError.NotFound;
    const sock = &sockets[handle];
    if (sock.kind != .tcp) return SocketError.Unsupported;
    if (sock.tcp_state != .established and sock.tcp_state != .peer_closed) return SocketError.NotConnected;
    if (!link.isReady()) return SocketError.NotReady;

    var spins: usize = 0;
    while (spins < max_spins) : (spins += 1) {
        if (sock.rx_len > 0) return drainRx(sock, buf);
        if (sock.tcp_state == .peer_closed) return 0;

        const seg = pollTcpSegment(sock, 1) catch return SocketError.IoError;
        if (seg) |s| {
            try ingestTcpSegment(sock, s);
            if (sock.rx_len > 0) return drainRx(sock, buf);
            if (sock.tcp_state == .peer_closed) return 0;
            continue;
        }
        asm volatile ("sti; pause; cli" ::: .{ .memory = true });
    }
    return SocketError.Timeout;
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
        .tcp => SocketError.Unsupported,
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
        .tcp => SocketError.Unsupported,
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
    const len = pump.pollFrame(&recv_buf, max_spins, pump.UdpMatcher{
        .local_port = local_port,
    }) catch |err| return socketErrorFromPump(err);

    var src_ip: ipv4.Addr = undefined;
    var src_port: u16 = 0;
    const payload = udp.match(recv_buf[0..len], local_port, &src_ip, &src_port) orelse return SocketError.IoError;
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

fn recvIcmp(
    handle: u32,
    buf: []u8,
    src_out: ?*SockaddrIn,
    max_spins: usize,
) SocketError!usize {
    const sock = &sockets[handle];
    const expect_seq = if (sock.icmp_seq > 0) sock.icmp_seq - 1 else 0;

    var recv_buf: [link.max_frame_len]u8 = undefined;
    const len = pump.pollFrame(&recv_buf, max_spins, pump.IcmpEchoMatcher{
        .id = sock.icmp_id,
        .sequence = expect_seq,
        .expected_src = sock.last_peer,
    }) catch |err| return socketErrorFromPump(err);

    var src_ip: ipv4.Addr = undefined;
    const payload = icmp.matchEchoReply(recv_buf[0..len], sock.icmp_id, expect_seq, &src_ip) orelse return SocketError.IoError;
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

fn tcpSendSegment(sock: *Socket, seq: u32, ack: u32, flags: u8, payload: []const u8) SocketError!void {
    const mac = link.localMac();
    const dst_mac = resolve.resolve(sock.remote_ip, mac) orelse return SocketError.IoError;
    const frame_len = tcp.build(
        &tcp_tx_frame,
        dst_mac,
        mac,
        config.guest_ip,
        sock.remote_ip,
        sock.local_port,
        sock.remote_port,
        seq,
        ack,
        flags,
        payload,
    );
    link.transmitOrFail(tcp_tx_frame[0..frame_len]) catch return SocketError.IoError;
}

fn pollTcpSegment(sock: *const Socket, max_spins: usize) SocketError!?tcp.Segment {
    const len = pump.pollFrame(&tcp_rx_scratch, max_spins, pump.TcpEndpointMatcher{
        .local_port = sock.local_port,
        .remote_ip = sock.remote_ip,
        .remote_port = sock.remote_port,
    }) catch |err| switch (err) {
        pump.Error.Timeout => return null,
        pump.Error.IoError => return SocketError.IoError,
    };
    return tcp.matchEndpoint(tcp_rx_scratch[0..len], sock.local_port, sock.remote_ip, sock.remote_port);
}

fn ingestTcpSegment(sock: *Socket, seg: tcp.Segment) SocketError!void {
    if (seg.flags & tcp.flag_rst != 0) return SocketError.IoError;

    if (seg.payload.len > 0 and seg.seq == sock.rcv_nxt) {
        const space = rx_buf_size - sock.rx_len;
        const copy = @min(seg.payload.len, space);
        if (copy > 0) {
            @memcpy(sock.rx_buf[sock.rx_len .. sock.rx_len + copy], seg.payload[0..copy]);
            sock.rx_len += copy;
        }
        sock.rcv_nxt +%= @intCast(seg.payload.len);
        try tcpSendSegment(sock, sock.snd_nxt, sock.rcv_nxt, tcp.flag_ack, "");
    }

    if (seg.flags & tcp.flag_fin != 0) {
        sock.rcv_nxt += 1;
        try tcpSendSegment(sock, sock.snd_nxt, sock.rcv_nxt, tcp.flag_ack, "");
        sock.tcp_state = .peer_closed;
    }
}

fn drainRx(sock: *Socket, buf: []u8) usize {
    const copy = @min(sock.rx_len, buf.len);
    @memcpy(buf[0..copy], sock.rx_buf[0..copy]);
    if (copy < sock.rx_len) {
        var i: usize = 0;
        while (i < sock.rx_len - copy) : (i += 1) {
            sock.rx_buf[i] = sock.rx_buf[copy + i];
        }
    }
    sock.rx_len -= copy;
    return copy;
}

pub fn putSockaddrIn(out: *SockaddrIn, ip: ipv4.Addr, port_host: u16) void {
    out.* = abi_net.sockaddrIn(ip, port_host);
}
