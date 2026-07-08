const config = @import("../config.zig");
const ipv4_addr = @import("common_ipv4_addr");
const link = @import("../link.zig");
const pump = @import("../pump.zig");
const resolve = @import("../resolve.zig");
const udp = @import("../udp.zig");
const api = @import("api.zig");
const table = @import("table.zig");

pub fn send(handle: u32, data: []const u8, dest: *const api.SockaddrIn) api.SocketError!usize {
    const sock = table.get(handle) orelse return api.SocketError.NotFound;
    const udp_sock = table.asUdp(sock) orelse return api.SocketError.Unsupported;
    if (!link.isReady()) return api.SocketError.NotReady;

    table.ensureLocalPort(sock);

    const dst_ip = ipv4_addr.Addr.fromOctets(dest.addr);
    const dst_port = @byteSwap(dest.port_be);
    const mac = link.localMac();
    const dst_mac = resolve.resolve(dst_ip, mac) orelse return api.SocketError.IoError;

    var frame: [link.max_frame_len]u8 = undefined;
    const frame_len = udp.build(
        &frame,
        dst_mac,
        mac,
        config.guest_ip,
        dst_ip,
        udp_sock.local_port,
        dst_port,
        data,
    );
    link.transmitOrFail(frame[0..frame_len]) catch return api.SocketError.IoError;
    return data.len;
}

pub fn recv(
    handle: u32,
    buf: []u8,
    src_out: ?*api.SockaddrIn,
    max_spins: usize,
) api.SocketError!usize {
    const sock = table.get(handle) orelse return api.SocketError.NotFound;
    const udp_sock = table.asUdp(sock) orelse return api.SocketError.Unsupported;
    if (udp_sock.local_port == 0) return api.SocketError.NotBound;
    if (!link.isReady()) return api.SocketError.NotReady;

    var recv_buf: [link.max_frame_len]u8 = undefined;
    const len = pump.pollFrame(&recv_buf, max_spins, pump.UdpMatcher{
        .local_port = udp_sock.local_port,
    }) catch |err| return api.socketErrorFromPump(err);

    var src_ip: @TypeOf(udp_sock.last_peer) = undefined;
    var src_port: u16 = 0;
    const payload = udp.match(recv_buf[0..len], udp_sock.local_port, &src_ip, &src_port) orelse return api.SocketError.IoError;
    const copy_len = @min(payload.len, buf.len);
    @memcpy(buf[0..copy_len], payload[0..copy_len]);
    if (src_out) |out| {
        api.putSockaddrIn(out, src_ip, src_port);
    }
    return copy_len;
}
