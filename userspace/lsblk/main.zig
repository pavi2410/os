const freestanding_std = @import("freestanding_std");
const libc = @import("libc");

pub const std_options_debug_io = freestanding_std.std_options_debug_io;
pub const std_options = freestanding_std.std_options;

const max_devices = 8;

var devices: [max_devices]libc.hw.BlockDeviceInfo = undefined;

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    _ = _argc;
    _ = _argv;

    const n = libc.hw.getblockdevices(&devices, max_devices);
    if (n < 0) {
        writeStr("lsblk: getblockdevices failed\n");
        libc.process.exit(1);
    }

    const count = @min(@as(usize, @intCast(n)), max_devices);
    writeStr("NAME             SIZE\n");

    var i: usize = 0;
    while (i < count) : (i += 1) {
        // Avoid copying BlockDeviceInfo to the stack: ReleaseSmall may emit movaps,
        // which faults if the stack frame is only 8-byte aligned.
        const name = libc.hw.zstr(devices[i].name[0..]);
        writeStr(name);
        var pad: usize = 17;
        if (name.len < 17) pad = 17 - name.len;
        while (pad > 0) : (pad -= 1) writeStr(" ");

        if (devices[i].sector_size == 0) {
            writeStr("0B\n");
            continue;
        }
        const bytes = blockBytes(devices[i].capacity_sectors, devices[i].sector_size);
        var size_buf: [32]u8 = undefined;
        writeStr(libc.hw.formatSize(bytes, &size_buf));
        writeStr("\n");
    }

    libc.process.exit(0);
}

fn blockBytes(capacity_sectors: u64, sector_size: u32) u64 {
    const wide = @as(u64, sector_size);
    const product, const overflow = @mulWithOverflow(capacity_sectors, wide);
    return if (overflow != 0) 0 else product;
}

fn writeStr(s: []const u8) void {
    libc.io.writeStr(s);
}
