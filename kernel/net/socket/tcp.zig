const config = @import("../config.zig");
const hal = @import("../../hal.zig");
const link = @import("../link.zig");
const pump = @import("../pump.zig");
const resolve = @import("../resolve.zig");
const tcp = @import("../tcp.zig");
const api = @import("api.zig");
const table = @import("table.zig");

var rx_scratch: [link.max_frame_len]u8 = undefined;
var tx_frame: [link.max_frame_len]u8 = undefined;

pub fn close(sock: *table.Socket) void {
    if (sock.kind == .tcp and sock.tcp_state == .established) {
        sendSegment(sock, sock.snd_nxt, sock.rcv_nxt, tcp.flag_fin | tcp.flag_ack, "") catch {};
    }
}

pub fn connect(handle: u32, addr: *const api.SockaddrIn) api.SocketError!void {
    const sock = table.get(handle) orelse return api.SocketError.NotFound;
    if (sock.kind != .tcp) return api.SocketError.Unsupported;
    if (addr.family != api.AF_INET) return api.SocketError.Unsupported;
    if (!link.isReady()) return api.SocketError.NotReady;
    if (sock.tcp_state != .closed) return api.SocketError.IoError;

    sock.remote_ip = addr.addr;
    sock.remote_port = @byteSwap(addr.port_be);
    sock.local_port = table.allocEphemeralPort();

    sock.snd_isn = table.allocIsn();

    try sendSegment(sock, sock.snd_isn, 0, tcp.flag_syn, "");
    sock.tcp_state = .syn_sent;

    const seg = (try pollSegment(sock, table.connect_spins)) orelse return api.SocketError.Timeout;

    if (seg.flags & (tcp.flag_syn | tcp.flag_ack) != (tcp.flag_syn | tcp.flag_ack)) return api.SocketError.IoError;
    if (seg.ack != sock.snd_isn + 1) return api.SocketError.IoError;

    sock.rcv_nxt = seg.seq + 1;
    sock.snd_nxt = sock.snd_isn + 1;
    try sendSegment(sock, sock.snd_nxt, sock.rcv_nxt, tcp.flag_ack, "");
    sock.tcp_state = .established;
}

pub fn send(handle: u32, data: []const u8) api.SocketError!usize {
    const sock = table.get(handle) orelse return api.SocketError.NotFound;
    if (sock.kind != .tcp) return api.SocketError.Unsupported;
    if (sock.tcp_state != .established) return api.SocketError.NotConnected;
    if (!link.isReady()) return api.SocketError.NotReady;

    const chunk = @min(data.len, table.max_tcp_segment);
    try sendSegment(sock, sock.snd_nxt, sock.rcv_nxt, tcp.flag_ack | tcp.flag_psh, data[0..chunk]);
    const expect_ack = sock.snd_nxt + @as(u32, @intCast(chunk));
    sock.snd_nxt = expect_ack;

    var spins: usize = 0;
    while (spins < table.send_spins) : (spins += 1) {
        const seg = pollSegment(sock, 1) catch return api.SocketError.IoError;
        if (seg) |s| {
            try ingestSegment(sock, s);
            if (s.flags & tcp.flag_ack != 0 and s.ack >= expect_ack) return chunk;
        }
    }
    return api.SocketError.Timeout;
}

pub fn recv(handle: u32, buf: []u8, max_spins: usize) api.SocketError!usize {
    const sock = table.get(handle) orelse return api.SocketError.NotFound;
    if (sock.kind != .tcp) return api.SocketError.Unsupported;
    if (sock.tcp_state != .established and sock.tcp_state != .peer_closed) return api.SocketError.NotConnected;
    if (!link.isReady()) return api.SocketError.NotReady;

    var spins: usize = 0;
    while (spins < max_spins) : (spins += 1) {
        if (sock.rx_len > 0) return drainRx(sock, buf);
        if (sock.tcp_state == .peer_closed) return 0;

        const seg = pollSegment(sock, 1) catch return api.SocketError.IoError;
        if (seg) |s| {
            try ingestSegment(sock, s);
            if (sock.rx_len > 0) return drainRx(sock, buf);
            if (sock.tcp_state == .peer_closed) return 0;
            continue;
        }
        hal.processor.relaxInterruptible();
    }
    return api.SocketError.Timeout;
}

fn sendSegment(sock: *table.Socket, seq: u32, ack: u32, flags: u8, payload: []const u8) api.SocketError!void {
    const mac = link.localMac();
    const dst_mac = resolve.resolve(sock.remote_ip, mac) orelse return api.SocketError.IoError;
    const frame_len = tcp.build(
        &tx_frame,
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
    link.transmitOrFail(tx_frame[0..frame_len]) catch return api.SocketError.IoError;
}

fn pollSegment(sock: *const table.Socket, max_spins: usize) api.SocketError!?tcp.Segment {
    const len = pump.pollFrame(&rx_scratch, max_spins, pump.TcpEndpointMatcher{
        .local_port = sock.local_port,
        .remote_ip = sock.remote_ip,
        .remote_port = sock.remote_port,
    }) catch |err| switch (err) {
        pump.Error.Timeout => return null,
        pump.Error.IoError => return api.SocketError.IoError,
    };
    return tcp.matchEndpoint(rx_scratch[0..len], sock.local_port, sock.remote_ip, sock.remote_port);
}

fn ingestSegment(sock: *table.Socket, seg: tcp.Segment) api.SocketError!void {
    if (seg.flags & tcp.flag_rst != 0) return api.SocketError.IoError;

    if (seg.payload.len > 0 and seg.seq == sock.rcv_nxt) {
        const space = table.rx_buf_size - sock.rx_len;
        const copy = @min(seg.payload.len, space);
        if (copy > 0) {
            @memcpy(sock.rx_buf[sock.rx_len .. sock.rx_len + copy], seg.payload[0..copy]);
            sock.rx_len += copy;
        }
        sock.rcv_nxt +%= @intCast(seg.payload.len);
        try sendSegment(sock, sock.snd_nxt, sock.rcv_nxt, tcp.flag_ack, "");
    }

    if (seg.flags & tcp.flag_fin != 0) {
        sock.rcv_nxt += 1;
        try sendSegment(sock, sock.snd_nxt, sock.rcv_nxt, tcp.flag_ack, "");
        sock.tcp_state = .peer_closed;
    }
}

fn drainRx(sock: *table.Socket, buf: []u8) usize {
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
