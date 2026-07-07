const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;

const ulib = @import("ulib");

const max_devices = 64;

var devices: [max_devices]ulib.hw.PciDeviceInfo = undefined;

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    _ = _argc;
    _ = _argv;

    const n = ulib.hw.getpcidevices(&devices, max_devices);
    if (n < 0) {
        writeStr("lspci: getpcidevices failed\n");
        ulib.process.exit(1);
    }

    var hex: [4]u8 = undefined;
    var byte_hex: [2]u8 = undefined;
    var i: usize = 0;
    while (i < @as(usize, @intCast(n))) : (i += 1) {
        const dev = devices[i];
        writeStr(ulib.hw.formatHexByte2(dev.bus, &byte_hex));
        writeStr(":");
        writeStr(ulib.hw.formatHexByte2(dev.device, &byte_hex));
        writeStr(".");
        ulib.io.writeU8(dev.function);
        writeStr(" ");

        writeStr(ulib.hw.formatHex16(dev.vendor_id, &hex));
        writeStr(":");
        writeStr(ulib.hw.formatHex16(dev.device_id, &hex));
        writeStr("  class ");
        writeStr(ulib.hw.formatHexByte(dev.class_code, &byte_hex));
        writeStr(":");
        writeStr(ulib.hw.formatHexByte(dev.subclass, &byte_hex));
        writeStr("  ");
        writeStr(ulib.hw.pciClassName(dev.class_code, dev.subclass));
        writeStr("\n");
    }

    ulib.process.exit(0);
}

fn writeStr(s: []const u8) void {
    ulib.io.writeStr(s);
}
