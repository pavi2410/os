const icmp = @import("icmp.zig");
const ipv4 = @import("ipv4.zig");
const link = @import("link.zig");
const tcp = @import("tcp.zig");
const udp = @import("udp.zig");

pub const Error = error{
    IoError,
    Timeout,
};

pub const UdpMatcher = struct {
    local_port: u16,

    pub fn matches(self: @This(), frame: []const u8) bool {
        var src_ip: ipv4.Addr = undefined;
        var src_port: u16 = 0;
        return udp.match(frame, self.local_port, &src_ip, &src_port) != null;
    }
};

pub const IcmpEchoMatcher = struct {
    id: u16,
    sequence: u16,
    expected_src: ipv4.Addr,

    pub fn matches(self: @This(), frame: []const u8) bool {
        return icmp.isEchoReply(frame, self.expected_src, self.id, self.sequence);
    }
};

pub const TcpEndpointMatcher = struct {
    local_port: u16,
    remote_ip: ipv4.Addr,
    remote_port: u16,

    pub fn matches(self: @This(), frame: []const u8) bool {
        return tcp.matchEndpoint(frame, self.local_port, self.remote_ip, self.remote_port) != null;
    }
};

pub fn pollFrame(buf: []u8, max_spins: usize, matcher: anytype) Error!usize {
    var spins: usize = 0;
    while (spins < max_spins) : (spins += 1) {
        const len = link.receive(buf) catch |err| switch (err) {
            error.NoPacket => {
                cpuRelaxInterruptible();
                continue;
            },
            else => return Error.IoError,
        };
        if (matcher.matches(buf[0..len])) return len;
    }
    return Error.Timeout;
}

fn cpuRelaxInterruptible() void {
    asm volatile ("sti; pause; cli" ::: .{ .memory = true });
}
