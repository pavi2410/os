const ipv4_addr = @import("common/ipv4_addr");
const std = @import("std");

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

/// Index into a Runtime-owned socket table.
pub const Handle = u32;

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
    refs: u16 = 0,
    active: Active = .{ .udp = .{} },

    pub const Active = union(Kind) {
        udp: UdpSocket,
        icmp: IcmpSocket,
        tcp: TcpSocket,
    };
};

/// Fixed-capacity socket ownership domain. New kernel composition code should
/// own one of these rather than relying on the compatibility default below.
pub const SocketTable = struct {
    sockets: [max_sockets]Socket = [_]Socket{.{}} ** max_sockets,
    next_ephemeral: u16 = ephemeral_port_min,
    next_icmp_id: u16 = 0x4000,
    next_isn: u32 = 0x12340000,

    pub fn init(self: *SocketTable) void { self.* = .{}; }
    pub fn get(self: *SocketTable, handle: Handle) ?*Socket {
        if (handle >= max_sockets or !self.sockets[handle].in_use) return null;
        return &self.sockets[handle];
    }
    pub fn create(self: *SocketTable, kind: Kind) ?Handle {
        for (&self.sockets, 0..) |*slot, i| {
            if (slot.in_use) continue;
            slot.* = switch (kind) {
                .udp => .{ .in_use = true, .refs = 1, .active = .{ .udp = .{} } },
                .icmp => .{ .in_use = true, .refs = 1, .active = .{ .icmp = .{ .icmp_id = self.allocIcmpId() } } },
                .tcp => .{ .in_use = true, .refs = 1, .active = .{ .tcp = .{} } },
            };
            return @intCast(i);
        }
        return null;
    }
    pub fn retain(self: *SocketTable, handle: Handle) bool {
        const sock = self.get(handle) orelse return false;
        if (sock.refs == std.math.maxInt(u16)) return false;
        sock.refs += 1;
        return true;
    }
    pub fn release(self: *SocketTable, handle: Handle) bool {
        const sock = self.get(handle) orelse return false;
        if (sock.refs == 0) return false;
        sock.refs -= 1;
        if (sock.refs != 0) return false;
        self.sockets[handle] = .{};
        return true;
    }
    pub fn allocEphemeralPort(self: *SocketTable) u16 {
        const port = self.next_ephemeral;
        self.next_ephemeral +%= 1;
        if (self.next_ephemeral < 1024) self.next_ephemeral = ephemeral_port_min;
        return port;
    }
    pub fn allocIcmpId(self: *SocketTable) u16 { const id = self.next_icmp_id; self.next_icmp_id +%= 1; return id; }
    pub fn allocIsn(self: *SocketTable) u32 { const isn = self.next_isn; self.next_isn +%= 65536; return isn; }
    pub fn ensureLocalPort(self: *SocketTable, sock: *Socket) void {
        switch (sock.active) {
            .udp => |*udp| {
                if (udp.local_port == 0) udp.local_port = self.allocEphemeralPort();
            },
            else => {},
        }
    }
};

/// Runtime-owned network socket service. Protocol caches will migrate into
/// this service alongside the table in the next network slice.
pub const Network = struct {
    sockets: SocketTable = .{},

    pub fn init(self: *Network) void { self.sockets.init(); }
};

var default_network: Network = .{};
var active: *Network = &default_network;
var default_table: *SocketTable = &default_network.sockets;

pub fn install(next: *Network) void {
    active = next;
    default_table = &active.sockets;
    active.init();
}

pub fn get(handle: u32) ?*Socket {
    return default_table.get(handle);
}

pub fn create(kind: Kind) ?u32 {
    return default_table.create(kind);
}

pub fn retain(handle: u32) bool {
    return default_table.retain(handle);
}

/// Returns true when the caller released the final reference.
pub fn release(handle: u32) bool {
    return default_table.release(handle);
}

pub fn allocEphemeralPort() u16 {
    return default_table.allocEphemeralPort();
}

pub fn allocIcmpId() u16 {
    return default_table.allocIcmpId();
}

pub fn allocIsn() u32 {
    return default_table.allocIsn();
}

pub fn ensureLocalPort(sock: *Socket) void {
    default_table.ensureLocalPort(sock);
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
