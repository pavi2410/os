const std = @import("std");
const socket_table = @import("socket_table");

test "create initializes kind-specific payloads" {
    const udp_handle = socket_table.create(.udp).?;
    const udp_sock = socket_table.get(udp_handle).?;
    try std.testing.expect(udp_sock.in_use);
    try std.testing.expect(udp_sock.active == .udp);
    try std.testing.expectEqual(@as(u16, 0), udp_sock.active.udp.local_port);

    const icmp_handle = socket_table.create(.icmp).?;
    const icmp_sock = socket_table.get(icmp_handle).?;
    try std.testing.expect(icmp_sock.active == .icmp);
    try std.testing.expect(icmp_sock.active.icmp.icmp_id >= 0x4000);

    const tcp_handle = socket_table.create(.tcp).?;
    const tcp_sock = socket_table.get(tcp_handle).?;
    try std.testing.expect(tcp_sock.active == .tcp);
    try std.testing.expect(tcp_sock.active.tcp.tcp_state == .closed);
}

test "typed accessors reject the wrong active tag" {
    const handle = socket_table.create(.udp).?;
    const sock = socket_table.get(handle).?;
    try std.testing.expect(socket_table.asUdp(sock) != null);
    try std.testing.expect(socket_table.asIcmp(sock) == null);
    try std.testing.expect(socket_table.asTcp(sock) == null);
}

test "ensureLocalPort only affects udp sockets" {
    const handle = socket_table.create(.udp).?;
    const sock = socket_table.get(handle).?;
    socket_table.ensureLocalPort(sock);
    try std.testing.expect(sock.active.udp.local_port >= socket_table.ephemeral_port_min);

    const icmp_handle = socket_table.create(.icmp).?;
    const icmp = socket_table.get(icmp_handle).?;
    socket_table.ensureLocalPort(icmp);
    try std.testing.expect(icmp.active.icmp.icmp_id >= 0x4000);
}

test "release clears slot back to default" {
    const handle = socket_table.create(.tcp).?;
    _ = socket_table.release(handle);
    const sock = socket_table.get(handle);
    try std.testing.expect(sock == null);
}

test "retained socket remains live until final release" {
    const handle = socket_table.create(.udp).?;
    try std.testing.expect(socket_table.retain(handle));
    try std.testing.expect(!socket_table.release(handle));
    try std.testing.expect(socket_table.get(handle) != null);
    try std.testing.expect(socket_table.release(handle));
    try std.testing.expect(socket_table.get(handle) == null);
}

test "tag coercion mirrors active socket kind" {
    const handle = socket_table.create(.tcp).?;
    const sock = socket_table.get(handle).?;
    try std.testing.expectEqual(socket_table.Kind.tcp, @as(socket_table.Kind, sock.active));
    try std.testing.expectEqualStrings("tcp", @tagName(sock.active));
}
