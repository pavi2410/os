const ethernet = @import("ethernet.zig");
const virtio_net = @import("../drivers/virtio_net.zig");

pub const max_frame_len = ethernet.max_frame_len;

pub const ReceiveError = error{
    NoPacket,
    IoError,
};

pub fn isReady() bool {
    return virtio_net.isReady();
}

pub fn localMac() ethernet.Mac {
    return virtio_net.macAddress();
}

pub fn transmitOrFail(frame: []const u8) virtio_net.NetError!void {
    try virtio_net.sendFrame(frame);
}

/// Spin until a frame arrives or `max_spins` is exhausted. Returns length or null.
pub fn pollReceive(buf: []u8, max_spins: usize) ?usize {
    return virtio_net.pollRecv(buf, max_spins) catch null;
}

pub fn receive(buf: []u8) ReceiveError!usize {
    return virtio_net.recvFrame(buf) catch |err| switch (err) {
        virtio_net.NetError.NoPacket => error.NoPacket,
        else => error.IoError,
    };
}
