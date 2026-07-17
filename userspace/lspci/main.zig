const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = _argc;
    _ = _argv;

    const fd = ulib.fs.open("/sys/bus/pci/devices", ulib.fs.O_RDONLY, 0);
    if (fd < 0) {
        ulib.io.writeStr("lspci: open /sys/bus/pci/devices failed\n");
        return 1;
    }
    defer _ = ulib.fs.close(@intCast(fd));

    var dent_buf: [1024]u8 = undefined;
    while (true) {
        const n = ulib.fs.getdents64(@intCast(fd), &dent_buf, dent_buf.len);
        if (n <= 0) break;
        var it = ulib.fs.Dirent64Iterator{ .data = dent_buf[0..@intCast(n)] };
        while (it.next()) |ent| {
            if (ent.name.len == 0 or ent.name[0] == '.') continue;
            printDevice(ent.name);
        }
    }
    return 0;
}

fn printDevice(addr: []const u8) void {
    var path_buf: [64]u8 = undefined;
    var vendor_buf: [16]u8 = undefined;
    var device_buf: [16]u8 = undefined;
    var class_buf: [16]u8 = undefined;

    const vendor = readAttr(addr, "vendor", &path_buf, &vendor_buf) orelse return;
    const device = readAttr(addr, "device", &path_buf, &device_buf) orelse return;
    const class_s = readAttr(addr, "class", &path_buf, &class_buf) orelse return;

    const vendor_id = parseHex(trimNl(vendor)) orelse return;
    const device_id = parseHex(trimNl(device)) orelse return;
    const class_packed = parseHex(trimNl(class_s)) orelse return;
    const class_code: u8 = @truncate((class_packed >> 16) & 0xFF);
    const subclass: u8 = @truncate((class_packed >> 8) & 0xFF);

    ulib.io.writeStr(addr);
    ulib.io.writeStr(" ");

    var hex: [4]u8 = undefined;
    var byte_hex: [2]u8 = undefined;
    ulib.io.writeStr(ulib.hw.formatHex16(@intCast(vendor_id), &hex));
    ulib.io.writeStr(":");
    ulib.io.writeStr(ulib.hw.formatHex16(@intCast(device_id), &hex));
    ulib.io.writeStr("  class ");
    ulib.io.writeStr(ulib.hw.formatHexByte(class_code, &byte_hex));
    ulib.io.writeStr(":");
    ulib.io.writeStr(ulib.hw.formatHexByte(subclass, &byte_hex));
    ulib.io.writeStr("  ");
    ulib.io.writeStr(ulib.hw.pciClassName(class_code, subclass));
    ulib.io.writeStr("\n");
}

fn readAttr(addr: []const u8, attr: []const u8, path_buf: []u8, out: []u8) ?[]const u8 {
    const prefix = "/sys/bus/pci/devices/";
    if (prefix.len + addr.len + 1 + attr.len + 1 > path_buf.len) return null;
    var p: usize = 0;
    @memcpy(path_buf[p .. p + prefix.len], prefix);
    p += prefix.len;
    @memcpy(path_buf[p .. p + addr.len], addr);
    p += addr.len;
    path_buf[p] = '/';
    p += 1;
    @memcpy(path_buf[p .. p + attr.len], attr);
    p += attr.len;
    path_buf[p] = 0;

    const fd = ulib.fs.open(@ptrCast(path_buf.ptr), ulib.fs.O_RDONLY, 0);
    if (fd < 0) return null;
    defer _ = ulib.fs.close(@intCast(fd));

    const n = ulib.fs.read(@intCast(fd), out.ptr, out.len);
    if (n <= 0) return null;
    return out[0..@intCast(n)];
}

fn trimNl(s: []const u8) []const u8 {
    var end = s.len;
    while (end > 0 and (s[end - 1] == '\n' or s[end - 1] == '\r' or s[end - 1] == ' ')) : (end -= 1) {}
    return s[0..end];
}

fn parseHex(s: []const u8) ?u32 {
    if (s.len == 0) return null;
    var v: u32 = 0;
    for (s) |c| {
        const nibble: u32 = if (c >= '0' and c <= '9')
            c - '0'
        else if (c >= 'a' and c <= 'f')
            c - 'a' + 10
        else if (c >= 'A' and c <= 'F')
            c - 'A' + 10
        else
            return null;
        v = (v << 4) | nibble;
    }
    return v;
}
