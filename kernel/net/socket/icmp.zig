const config = @import("../config.zig");
const icmp = @import("../icmp.zig");
const link = @import("../link.zig");
const pump = @import("../pump.zig");
const resolve = @import("../resolve.zig");
const api = @import("api.zig");
const table = @import("table.zig");

pub fn send(handle: u32, dest: *const api.SockaddrIn) api.SocketError!usize {
    const sock = table.get(handle) orelse return api.SocketError.NotFound;
    if (!link.isReady()) return api.SocketError.NotReady;

    const dst_ip = dest.addr;
    const mac = link.localMac();
    const dst_mac = resolve.resolve(dst_ip, mac) orelse return api.SocketError.IoError;

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
    link.transmitOrFail(frame[0..frame_len]) catch return api.SocketError.IoError;
    return icmp.echo_payload_len;
}

pub fn recv(
    handle: u32,
    buf: []u8,
    src_out: ?*api.SockaddrIn,
    max_spins: usize,
) api.SocketError!usize {
    const sock = table.get(handle) orelse return api.SocketError.NotFound;
    if (!link.isReady()) return api.SocketError.NotReady;

    const expect_seq = if (sock.icmp_seq > 0) sock.icmp_seq - 1 else 0;

    var recv_buf: [link.max_frame_len]u8 = undefined;
    const len = pump.pollFrame(&recv_buf, max_spins, pump.IcmpEchoMatcher{
        .id = sock.icmp_id,
        .sequence = expect_seq,
        .expected_src = sock.last_peer,
    }) catch |err| return api.socketErrorFromPump(err);

    var src_ip: @TypeOf(sock.last_peer) = undefined;
    const payload = icmp.matchEchoReply(recv_buf[0..len], sock.icmp_id, expect_seq, &src_ip) orelse return api.SocketError.IoError;
    const copy_len = @min(payload.len, buf.len);
    @memcpy(buf[0..copy_len], payload[0..copy_len]);
    if (src_out) |out| {
        api.putSockaddrIn(out, src_ip, 0);
    }
    return copy_len;
}
