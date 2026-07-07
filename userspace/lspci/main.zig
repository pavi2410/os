const freestanding_std = @import("freestanding_std");
const libc = @import("libc");

pub const std_options_debug_io = freestanding_std.std_options_debug_io;
pub const std_options = freestanding_std.std_options;

const max_devices = 64;

var devices: [max_devices]libc.hw.PciDeviceInfo = undefined;

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    _ = _argc;
    _ = _argv;

    const n = libc.hw.getpcidevices(&devices, max_devices);
    if (n < 0) {
        writeStr("lspci: getpcidevices failed\n");
        libc.process.exit(1);
    }

    var hex: [4]u8 = undefined;
    var byte_hex: [2]u8 = undefined;
    var i: usize = 0;
    while (i < @as(usize, @intCast(n))) : (i += 1) {
        const dev = devices[i];
        writeStr(libc.hw.formatHexByte2(dev.bus, &byte_hex));
        writeStr(":");
        writeStr(libc.hw.formatHexByte2(dev.device, &byte_hex));
        writeStr(".");
        libc.io.writeU8(dev.function);
        writeStr(" ");

        writeStr(libc.hw.formatHex16(dev.vendor_id, &hex));
        writeStr(":");
        writeStr(libc.hw.formatHex16(dev.device_id, &hex));
        writeStr("  class ");
        writeStr(libc.hw.formatHexByte(dev.class_code, &byte_hex));
        writeStr(":");
        writeStr(libc.hw.formatHexByte(dev.subclass, &byte_hex));
        writeStr("  ");
        writeStr(libc.hw.pciClassName(dev.class_code, dev.subclass));
        writeStr("\n");
    }

    libc.process.exit(0);
}

fn writeStr(s: []const u8) void {
    libc.io.writeStr(s);
}
