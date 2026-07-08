const ipv4_addr = @import("common/ipv4_addr");

pub const Addr = ipv4_addr.Addr;

pub const rx_buf_size = 8192;
pub const max_sockets = 16;
pub const ephemeral_port_min: u16 = 49152;
pub const max_tcp_segment = 1400;
pub const connect_spins: usize = 500_000;
pub const send_spins: usize = 500_000;

pub const Kind = enum {
    udp,
    icmp,
    tcp,
};

pub const TcpState = enum {
    closed,
    syn_sent,
    established,
    peer_closed,
};

pub const UdpSocket = struct {
    local_port: u16 = 0,
    last_peer: Addr = Addr.zero,
};

pub const IcmpSocket = struct {
    icmp_id: u16 = 0,
    icmp_seq: u16 = 0,
    last_peer: Addr = Addr.zero,
};

pub const TcpSocket = struct {
    local_port: u16 = 0,
    tcp_state: TcpState = .closed,
    remote_ip: Addr = Addr.zero,
    remote_port: u16 = 0,
    snd_isn: u32 = 0,
    snd_nxt: u32 = 0,
    rcv_nxt: u32 = 0,
    rx_buf: [rx_buf_size]u8 = undefined,
    rx_len: usize = 0,
};

pub const Socket = struct {
    in_use: bool = false,
    active: Active = .{ .udp = .{} },

    pub const Active = union(Kind) {
        udp: UdpSocket,
        icmp: IcmpSocket,
        tcp: TcpSocket,
    };
};

var sockets: [max_sockets]Socket = [_]Socket{.{}} ** max_sockets;
var next_ephemeral: u16 = ephemeral_port_min;
var next_icmp_id: u16 = 0x4000;
var next_isn: u32 = 0x12340000;

pub fn get(handle: u32) ?*Socket {
    if (handle >= max_sockets) return null;
    const sock = &sockets[handle];
    if (!sock.in_use) return null;
    return sock;
}

pub fn create(kind: Kind) ?u32 {
    var i: usize = 0;
    while (i < max_sockets) : (i += 1) {
        if (!sockets[i].in_use) {
            sockets[i] = switch (kind) {
                .udp => .{ .in_use = true, .active = .{ .udp = .{} } },
                .icmp => .{
                    .in_use = true,
                    .active = .{ .icmp = .{ .icmp_id = allocIcmpId() } },
                },
                .tcp => .{ .in_use = true, .active = .{ .tcp = .{} } },
            };
            return @intCast(i);
        }
    }
    return null;
}

pub fn release(handle: u32) void {
    if (handle >= max_sockets) return;
    sockets[handle] = .{};
}

pub fn allocEphemeralPort() u16 {
    const port = next_ephemeral;
    next_ephemeral +%= 1;
    if (next_ephemeral < 1024) next_ephemeral = ephemeral_port_min;
    return port;
}

pub fn allocIcmpId() u16 {
    const id = next_icmp_id;
    next_icmp_id +%= 1;
    return id;
}

pub fn allocIsn() u32 {
    const isn = next_isn;
    next_isn +%= 65536;
    return isn;
}

pub fn ensureLocalPort(sock: *Socket) void {
    switch (sock.active) {
        .udp => |*udp_sock| {
            if (udp_sock.local_port == 0) {
                udp_sock.local_port = allocEphemeralPort();
            }
        },
        else => {},
    }
}

pub fn asUdp(sock: *Socket) ?*UdpSocket {
    return switch (sock.active) {
        .udp => |*udp_sock| udp_sock,
        else => null,
    };
}

pub fn asIcmp(sock: *Socket) ?*IcmpSocket {
    return switch (sock.active) {
        .icmp => |*icmp_sock| icmp_sock,
        else => null,
    };
}

pub fn asTcp(sock: *Socket) ?*TcpSocket {
    return switch (sock.active) {
        .tcp => |*tcp_sock| tcp_sock,
        else => null,
    };
}
