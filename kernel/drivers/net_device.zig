pub const Mac = [6]u8;

pub const Error = error{
    NotReady,
    IoError,
    Timeout,
    BufferTooSmall,
    NoPacket,
};

pub const Device = struct {
    name: []const u8,
    max_frame_size: usize,
    ctx: ?*anyopaque = null,
    is_ready: *const fn (?*anyopaque) bool,
    mac_address: *const fn (?*anyopaque) Mac,
    send_frame: *const fn (?*anyopaque, frame: []const u8) Error!void,
    recv_frame: *const fn (?*anyopaque, buf: []u8) Error!usize,
    poll_recv: *const fn (?*anyopaque, buf: []u8, max_spins: usize) Error!usize,

    pub fn isReady(self: *const Device) bool {
        return self.is_ready(self.ctx);
    }

    pub fn macAddress(self: *const Device) Mac {
        return self.mac_address(self.ctx);
    }

    pub fn sendFrame(self: *const Device, frame: []const u8) Error!void {
        try self.send_frame(self.ctx, frame);
    }

    pub fn recvFrame(self: *const Device, buf: []u8) Error!usize {
        return self.recv_frame(self.ctx, buf);
    }

    pub fn pollRecv(self: *const Device, buf: []u8, max_spins: usize) Error!usize {
        return self.poll_recv(self.ctx, buf, max_spins);
    }
};

var default_device: ?Device = null;

pub fn registerDefault(device: Device) void {
    default_device = device;
}

pub fn default() ?*const Device {
    if (default_device) |*device| return device;
    return null;
}

pub fn clearDefaultForTest() void {
    default_device = null;
}
