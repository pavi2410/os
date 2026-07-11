const config = @import("../config.zig");
const hal = @import("../../hal.zig");
const ipv4_addr = @import("common/ipv4_addr");
const link = @import("../link.zig");
const pump = @import("../pump.zig");
const resolve = @import("../resolve.zig");
const scheduler = @import("../../proc/scheduler.zig");
const tcp = @import("../tcp.zig");
const api = @import("api.zig");
const table = @import("table.zig");

var rx_scratch: [link.max_frame_len]u8 = undefined;
var tx_frame: [link.max_frame_len]u8 = undefined;

pub fn close(sock: *table.Socket) void {
    const tcp_sock = table.asTcp(sock) orelse return;
    if (tcp_sock.tcp_state == .established) {
        sendSegment(tcp_sock, tcp_sock.snd_nxt, tcp_sock.rcv_nxt, .{ .fin = 1, .ack = 1 }, "") catch {};
    }
}

pub fn connect(sockets: *table.SocketTable, handle: table.Handle, addr: *const api.SockaddrIn) api.SocketError!void {
    const sock = sockets.get(handle) orelse return api.SocketError.NotFound;
    const tcp_sock = table.asTcp(sock) orelse return api.SocketError.Unsupported;
    if (api.sockaddrFamily(addr) != .inet) return api.SocketError.Unsupported;
    if (!link.isReady()) return api.SocketError.NotReady;
    if (tcp_sock.tcp_state != .closed) return api.SocketError.IoError;

    tcp_sock.remote_ip = ipv4_addr.Addr.fromOctets(addr.addr);
    tcp_sock.remote_port = @byteSwap(addr.port_be);
    tcp_sock.local_port = sockets.allocEphemeralPort();

    tcp_sock.snd_isn = sockets.allocIsn();

    try sendSegment(tcp_sock, tcp_sock.snd_isn, 0, .{ .syn = 1 }, "");
    tcp_sock.tcp_state = .syn_sent;

    const seg = (try pollSegment(tcp_sock, table.connect_spins)) orelse return api.SocketError.Timeout;

    if (seg.flags.syn != 1 or seg.flags.ack != 1) return api.SocketError.IoError;
    if (seg.ack != tcp_sock.snd_isn + 1) return api.SocketError.IoError;

    tcp_sock.rcv_nxt = seg.seq + 1;
    tcp_sock.snd_nxt = tcp_sock.snd_isn + 1;
    try sendSegment(tcp_sock, tcp_sock.snd_nxt, tcp_sock.rcv_nxt, .{ .ack = 1 }, "");
    tcp_sock.tcp_state = .established;
}

pub fn send(sockets: *table.SocketTable, handle: table.Handle, data: []const u8) api.SocketError!usize {
    const sock = sockets.get(handle) orelse return api.SocketError.NotFound;
    const tcp_sock = table.asTcp(sock) orelse return api.SocketError.Unsupported;
    if (tcp_sock.tcp_state != .established) return api.SocketError.NotConnected;
    if (!link.isReady()) return api.SocketError.NotReady;

    const chunk = @min(data.len, table.max_tcp_segment);
    try sendSegment(tcp_sock, tcp_sock.snd_nxt, tcp_sock.rcv_nxt, .{ .ack = 1, .psh = 1 }, data[0..chunk]);
    const expect_ack = tcp_sock.snd_nxt + @as(u32, @intCast(chunk));
    tcp_sock.snd_nxt = expect_ack;

    var spins: usize = 0;
    while (spins < table.send_spins) : (spins += 1) {
        const seg = pollSegment(tcp_sock, 1) catch return api.SocketError.IoError;
        if (seg) |s| {
            try ingestSegment(tcp_sock, s);
            if (s.flags.ack != 0 and s.ack >= expect_ack) return chunk;
        }
    }
    return api.SocketError.Timeout;
}

pub fn recv(sockets: *table.SocketTable, handle: table.Handle, buf: []u8, max_spins: usize) api.SocketError!usize {
    const sock = sockets.get(handle) orelse return api.SocketError.NotFound;
    const tcp_sock = table.asTcp(sock) orelse return api.SocketError.Unsupported;
    if (tcp_sock.tcp_state != .established and tcp_sock.tcp_state != .peer_closed) return api.SocketError.NotConnected;
    if (!link.isReady()) return api.SocketError.NotReady;

    var spins: usize = 0;
    while (spins < max_spins) : (spins += 1) {
        if (tcp_sock.rx_len > 0) return drainRx(tcp_sock, buf);
        if (tcp_sock.tcp_state == .peer_closed) return 0;

        const seg = pollSegment(tcp_sock, 1) catch return api.SocketError.IoError;
        if (seg) |s| {
            try ingestSegment(tcp_sock, s);
            if (tcp_sock.rx_len > 0) return drainRx(tcp_sock, buf);
            if (tcp_sock.tcp_state == .peer_closed) return 0;
            continue;
        }
        hal.processor.relaxInterruptible();
        scheduler.cooperativePoll();
    }
    return api.SocketError.Timeout;
}

fn sendSegment(tcp_sock: *table.TcpSocket, seq: u32, ack: u32, flags: tcp.Flags, payload: []const u8) api.SocketError!void {
    const mac = link.localMac();
    const dst_mac = resolve.resolve(tcp_sock.remote_ip, mac) orelse return api.SocketError.IoError;
    const frame_len = tcp.build(
        &tx_frame,
        dst_mac,
        mac,
        config.guest_ip,
        tcp_sock.remote_ip,
        tcp_sock.local_port,
        tcp_sock.remote_port,
        seq,
        ack,
        flags,
        payload,
    );
    link.transmitOrFail(tx_frame[0..frame_len]) catch return api.SocketError.IoError;
}

fn pollSegment(tcp_sock: *const table.TcpSocket, max_spins: usize) api.SocketError!?tcp.Segment {
    const len = pump.pollFrame(&rx_scratch, max_spins, pump.TcpEndpointMatcher{
        .local_port = tcp_sock.local_port,
        .remote_ip = tcp_sock.remote_ip,
        .remote_port = tcp_sock.remote_port,
    }) catch |err| switch (err) {
        pump.Error.Timeout => return null,
        pump.Error.IoError => return api.SocketError.IoError,
    };
    return tcp.matchEndpoint(rx_scratch[0..len], tcp_sock.local_port, tcp_sock.remote_ip, tcp_sock.remote_port);
}

fn ingestSegment(tcp_sock: *table.TcpSocket, seg: tcp.Segment) api.SocketError!void {
    if (seg.flags.rst != 0) return api.SocketError.IoError;

    if (seg.payload.len > 0 and seg.seq == tcp_sock.rcv_nxt) {
        const space = table.rx_buf_size - tcp_sock.rx_len;
        const copy = @min(seg.payload.len, space);
        if (copy > 0) {
            @memcpy(tcp_sock.rx_buf[tcp_sock.rx_len .. tcp_sock.rx_len + copy], seg.payload[0..copy]);
            tcp_sock.rx_len += copy;
        }
        tcp_sock.rcv_nxt +%= @intCast(seg.payload.len);
        try sendSegment(tcp_sock, tcp_sock.snd_nxt, tcp_sock.rcv_nxt, .{ .ack = 1 }, "");
    }

    if (seg.flags.fin != 0) {
        tcp_sock.rcv_nxt += 1;
        try sendSegment(tcp_sock, tcp_sock.snd_nxt, tcp_sock.rcv_nxt, .{ .ack = 1 }, "");
        tcp_sock.tcp_state = .peer_closed;
    }
}

fn drainRx(tcp_sock: *table.TcpSocket, buf: []u8) usize {
    const copy = @min(tcp_sock.rx_len, buf.len);
    @memcpy(buf[0..copy], tcp_sock.rx_buf[0..copy]);
    if (copy < tcp_sock.rx_len) {
        var i: usize = 0;
        while (i < tcp_sock.rx_len - copy) : (i += 1) {
            tcp_sock.rx_buf[i] = tcp_sock.rx_buf[copy + i];
        }
    }
    tcp_sock.rx_len -= copy;
    return copy;
}
