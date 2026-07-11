const std = @import("std");
const socket_table = @import("socket_table");

test "create initializes kind-specific payloads" {
    var sockets: socket_table.Network = .{};
    const udp_handle = sockets.create(.udp).?;
    const udp_sock = sockets.get(udp_handle).?;
    try std.testing.expect(udp_sock.in_use);
    try std.testing.expect(udp_sock.active == .udp);
    try std.testing.expectEqual(@as(u16, 0), udp_sock.active.udp.local_port);

    const icmp_handle = sockets.create(.icmp).?;
    const icmp_sock = sockets.get(icmp_handle).?;
    try std.testing.expect(icmp_sock.active == .icmp);
    try std.testing.expect(icmp_sock.active.icmp.icmp_id >= 0x4000);

    const tcp_handle = sockets.create(.tcp).?;
    const tcp_sock = sockets.get(tcp_handle).?;
    try std.testing.expect(tcp_sock.active == .tcp);
    try std.testing.expect(tcp_sock.active.tcp.tcp_state == .closed);
}

test "typed accessors reject the wrong active tag" {
    var sockets: socket_table.Network = .{};
    const handle = sockets.create(.udp).?;
    const sock = sockets.get(handle).?;
    try std.testing.expect(socket_table.asUdp(sock) != null);
    try std.testing.expect(socket_table.asIcmp(sock) == null);
    try std.testing.expect(socket_table.asTcp(sock) == null);
}

test "ensureLocalPort only affects udp sockets" {
    var sockets: socket_table.Network = .{};
    const handle = sockets.create(.udp).?;
    const sock = sockets.get(handle).?;
    sockets.ensureLocalPort(sock);
    try std.testing.expect(sock.active.udp.local_port >= socket_table.ephemeral_port_min);

    const icmp_handle = sockets.create(.icmp).?;
    const icmp = sockets.get(icmp_handle).?;
    sockets.ensureLocalPort(icmp);
    try std.testing.expect(icmp.active.icmp.icmp_id >= 0x4000);
}

test "release clears slot back to default" {
    var sockets: socket_table.Network = .{};
    const handle = sockets.create(.tcp).?;
    _ = sockets.release(handle);
    const sock = sockets.get(handle);
    try std.testing.expect(sock == null);
}

test "retained socket remains live until final release" {
    var sockets: socket_table.Network = .{};
    const handle = sockets.create(.udp).?;
    try std.testing.expect(sockets.retain(handle));
    try std.testing.expect(!sockets.release(handle));
    try std.testing.expect(sockets.get(handle) != null);
    try std.testing.expect(sockets.release(handle));
    try std.testing.expect(sockets.get(handle) == null);
}

test "release rejects a corrupted zero-reference live slot" {
    var table: socket_table.SocketTable = .{};
    const handle = table.create(.udp).?;
    table.get(handle).?.refs = 0;

    try std.testing.expect(!table.release(handle));
    try std.testing.expect(table.get(handle) != null);
}

test "tag coercion mirrors active socket kind" {
    var sockets: socket_table.Network = .{};
    const handle = sockets.create(.tcp).?;
    const sock = sockets.get(handle).?;
    try std.testing.expectEqual(socket_table.Kind.tcp, @as(socket_table.Kind, sock.active));
    try std.testing.expectEqualStrings("tcp", @tagName(sock.active));
}

test "independent socket tables own their allocation cursors" {
    var left: socket_table.SocketTable = .{};
    var right: socket_table.SocketTable = .{};
    const left_handle = left.create(.icmp).?;
    const right_handle = right.create(.icmp).?;
    try std.testing.expectEqual(@as(u32, 0), left_handle);
    try std.testing.expectEqual(@as(u32, 0), right_handle);
    try std.testing.expectEqual(@as(u16, 0x4000), left.get(left_handle).?.active.icmp.icmp_id);
    try std.testing.expectEqual(@as(u16, 0x4000), right.get(right_handle).?.active.icmp.icmp_id);
}
