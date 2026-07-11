const config = @import("../config.zig");
const icmp = @import("../icmp.zig");
const ipv4_addr = @import("common/ipv4_addr");
const link = @import("../link.zig");
const pump = @import("../pump.zig");
const resolve = @import("../resolve.zig");
const api = @import("api.zig");
const table = @import("table.zig");

pub fn send(sockets: *table.SocketTable, handle: table.Handle, dest: *const api.SockaddrIn) api.SocketError!usize {
    const sock = sockets.get(handle) orelse return api.SocketError.NotFound;
    const icmp_sock = table.asIcmp(sock) orelse return api.SocketError.Unsupported;
    if (!link.isReady()) return api.SocketError.NotReady;

    const dst_ip = ipv4_addr.Addr.fromOctets(dest.addr);
    const mac = link.localMac();
    const dst_mac = resolve.resolve(dst_ip, mac) orelse return api.SocketError.IoError;

    const sequence = icmp_sock.icmp_seq;
    icmp_sock.icmp_seq +%= 1;
    icmp_sock.last_peer = dst_ip;

    var frame: [link.max_frame_len]u8 = undefined;
    const frame_len = icmp.buildEchoRequest(
        &frame,
        dst_mac,
        mac,
        config.guest_ip,
        dst_ip,
        icmp_sock.icmp_id,
        sequence,
    );
    link.transmitOrFail(frame[0..frame_len]) catch return api.SocketError.IoError;
    return icmp.echo_payload_len;
}

pub fn recv(
    sockets: *table.SocketTable,
    handle: table.Handle,
    buf: []u8,
    src_out: ?*api.SockaddrIn,
    max_spins: usize,
) api.SocketError!usize {
    const sock = sockets.get(handle) orelse return api.SocketError.NotFound;
    const icmp_sock = table.asIcmp(sock) orelse return api.SocketError.Unsupported;
    if (!link.isReady()) return api.SocketError.NotReady;

    const expect_seq = if (icmp_sock.icmp_seq > 0) icmp_sock.icmp_seq - 1 else 0;

    var recv_buf: [link.max_frame_len]u8 = undefined;
    const len = pump.pollFrame(&recv_buf, max_spins, pump.IcmpEchoMatcher{
        .id = icmp_sock.icmp_id,
        .sequence = expect_seq,
        .expected_src = icmp_sock.last_peer,
    }) catch |err| return api.socketErrorFromPump(err);

    var src_ip: @TypeOf(icmp_sock.last_peer) = undefined;
    const payload = icmp.matchEchoReply(recv_buf[0..len], icmp_sock.icmp_id, expect_seq, &src_ip) orelse return api.SocketError.IoError;
    const copy_len = @min(payload.len, buf.len);
    @memcpy(buf[0..copy_len], payload[0..copy_len]);
    if (src_out) |out| {
        api.putSockaddrIn(out, src_ip, 0);
    }
    return copy_len;
}
