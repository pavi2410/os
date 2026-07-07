const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;

const ulib = @import("ulib");

const max_devices = 64;

var devices: [max_devices]ulib.hw.PciDeviceInfo = undefined;

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = _argc;
    _ = _argv;

    const n = ulib.hw.getpcidevices(&devices, max_devices);
    if (n < 0) {
        ulib.io.writeStr("lspci: getpcidevices failed\n");
        return 1;
    }

    var hex: [4]u8 = undefined;
    var byte_hex: [2]u8 = undefined;
    var i: usize = 0;
    while (i < @as(usize, @intCast(n))) : (i += 1) {
        const dev = devices[i];
        ulib.io.writeStr(ulib.hw.formatHexByte2(dev.bus, &byte_hex));
        ulib.io.writeStr(":");
        ulib.io.writeStr(ulib.hw.formatHexByte2(dev.device, &byte_hex));
        ulib.io.writeStr(".");
        ulib.io.writeU8(dev.function);
        ulib.io.writeStr(" ");

        ulib.io.writeStr(ulib.hw.formatHex16(dev.vendor_id, &hex));
        ulib.io.writeStr(":");
        ulib.io.writeStr(ulib.hw.formatHex16(dev.device_id, &hex));
        ulib.io.writeStr("  class ");
        ulib.io.writeStr(ulib.hw.formatHexByte(dev.class_code, &byte_hex));
        ulib.io.writeStr(":");
        ulib.io.writeStr(ulib.hw.formatHexByte(dev.subclass, &byte_hex));
        ulib.io.writeStr("  ");
        ulib.io.writeStr(ulib.hw.pciClassName(dev.class_code, dev.subclass));
        ulib.io.writeStr("\n");
    }

    return 0;
}
