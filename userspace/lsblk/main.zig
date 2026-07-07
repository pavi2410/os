const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;

const ulib = @import("ulib");

const max_devices = 8;

var devices: [max_devices]ulib.hw.BlockDeviceInfo = undefined;

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    _ = _argc;
    _ = _argv;

    const n = ulib.hw.getblockdevices(&devices, max_devices);
    if (n < 0) {
        ulib.io.writeStr("lsblk: getblockdevices failed\n");
        ulib.process.exit(1);
    }

    const count = @min(@as(usize, @intCast(n)), max_devices);
    ulib.io.writeStr("NAME             SIZE\n");

    var i: usize = 0;
    while (i < count) : (i += 1) {
        // Avoid copying BlockDeviceInfo to the stack: ReleaseSmall may emit movaps,
        // which faults if the stack frame is only 8-byte aligned.
        const name = ulib.hw.zstr(devices[i].name[0..]);
        ulib.io.writeStr(name);
        var pad: usize = 17;
        if (name.len < 17) pad = 17 - name.len;
        while (pad > 0) : (pad -= 1) ulib.io.writeStr(" ");

        if (devices[i].sector_size == 0) {
            ulib.io.writeStr("0B\n");
            continue;
        }
        const bytes = blockBytes(devices[i].capacity_sectors, devices[i].sector_size);
        var size_buf: [32]u8 = undefined;
        ulib.io.writeStr(ulib.hw.formatSize(bytes, &size_buf));
        ulib.io.writeStr("\n");
    }

    ulib.process.exit(0);
}

fn blockBytes(capacity_sectors: u64, sector_size: u32) u64 {
    const wide = @as(u64, sector_size);
    const product, const overflow = @mulWithOverflow(capacity_sectors, wide);
    return if (overflow != 0) 0 else product;
}
