const ethernet = @import("ethernet.zig");
const mac = @import("common/mac");
const net_device = @import("../drivers/net_device.zig");

pub const max_frame_len = ethernet.max_frame_len;

pub const ReceiveError = error{
    NoPacket,
    IoError,
};

pub fn isReady() bool {
    const dev = net_device.default() orelse return false;
    return dev.isReady();
}

pub fn localMac() mac.Mac {
    const dev = net_device.default() orelse return mac.Mac.zero;
    return mac.Mac.fromOctets(dev.macAddress());
}

pub fn transmitOrFail(frame: []const u8) net_device.Error!void {
    const dev = net_device.default() orelse return net_device.Error.NotReady;
    try dev.sendFrame(frame);
}

/// Spin until a frame arrives or `max_spins` is exhausted. Returns length or null.
pub fn pollReceive(buf: []u8, max_spins: usize) ?usize {
    const dev = net_device.default() orelse return null;
    return dev.pollRecv(buf, max_spins) catch null;
}

pub fn receive(buf: []u8) ReceiveError!usize {
    const dev = net_device.default() orelse return error.IoError;
    return dev.recvFrame(buf) catch |err| switch (err) {
        net_device.Error.NoPacket => error.NoPacket,
        else => error.IoError,
    };
}
