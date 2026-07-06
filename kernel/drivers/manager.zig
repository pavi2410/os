const hal = @import("../hal.zig");
const virtio_blk = @import("virtio_blk.zig");
const virtio_net = @import("virtio_net.zig");

pub fn initBlock() bool {
    virtio_blk.init() catch {
        hal.console.writeString("virtio-blk not available\r\n");
        return false;
    };
    virtio_blk.logStatus();
    return true;
}

pub fn initNetwork() bool {
    virtio_net.init() catch {
        hal.console.writeString("virtio-net not available\r\n");
        return false;
    };
    virtio_net.logStatus();
    return true;
}
