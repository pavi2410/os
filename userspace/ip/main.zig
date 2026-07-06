const freestanding_std = @import("freestanding_std");
const libc = @import("libc");

pub const std_options_debug_io = freestanding_std.std_options_debug_io;
pub const std_options = freestanding_std.std_options;

const iface_name = "eth0";

export fn main(argc: usize, argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    if (argc < 2) {
        printUsage();
        libc.syscall.exit(1);
    }

    const sub = cstr(argv[1]);
    if (eql(sub, "addr") or eql(sub, "a")) {
        cmdAddr();
    } else if (eql(sub, "route") or eql(sub, "r")) {
        cmdRoute();
    } else if (eql(sub, "neigh") or eql(sub, "n")) {
        cmdNeigh();
    } else {
        writeStr("ip: unknown subcommand '");
        writeStr(sub);
        writeStr("'\n");
        printUsage();
        libc.syscall.exit(1);
    }

    libc.syscall.exit(0);
}

fn printUsage() void {
    writeStr("usage: ip <addr|route|neigh>\n");
}

fn cmdAddr() void {
    var cfg: libc.syscall.NetConfig = undefined;
    if (libc.syscall.getnetconfig(&cfg) < 0) {
        writeStr("ip: getnetconfig failed\n");
        libc.syscall.exit(1);
    }

    writeStr(iface_name);
    writeStr(": <BROADCAST,MULTICAST,UP> mtu 1500\n");
    writeStr("    inet ");
    writeIpv4(cfg.ip);
    writeStr("/");
    writeDecimal(maskPrefix(cfg.mask));
    writeStr(" scope global ");
    writeStr(iface_name);
    writeStr("\n    link/ether ");
    writeMac(cfg.mac);
    writeStr(" brd ff:ff:ff:ff:ff:ff\n");
}

fn cmdRoute() void {
    var cfg: libc.syscall.NetConfig = undefined;
    if (libc.syscall.getnetconfig(&cfg) < 0) {
        writeStr("ip: getnetconfig failed\n");
        libc.syscall.exit(1);
    }

    writeStr("default via ");
    writeIpv4(cfg.gateway);
    writeStr(" dev ");
    writeStr(iface_name);
    writeStr("\n");

    writeStr("network ");
    writeIpv4(networkAddr(cfg.ip, cfg.mask));
    writeStr("/");
    writeDecimal(maskPrefix(cfg.mask));
    writeStr(" dev ");
    writeStr(iface_name);
    writeStr(" scope link\n");
}

fn cmdNeigh() void {
    var entries: [8]libc.syscall.NeighEntry = undefined;
    const n = libc.syscall.getneighbors(&entries, entries.len);
    if (n < 0) {
        writeStr("ip: getneighbors failed\n");
        libc.syscall.exit(1);
    }

    var i: usize = 0;
    while (i < @as(usize, @intCast(n))) : (i += 1) {
        writeIpv4(entries[i].ip);
        writeStr(" dev ");
        writeStr(iface_name);
        writeStr(" lladdr ");
        writeMac(entries[i].mac);
        writeStr(" REACHABLE\n");
    }
}

fn networkAddr(ip: [4]u8, mask: [4]u8) [4]u8 {
    return .{
        ip[0] & mask[0],
        ip[1] & mask[1],
        ip[2] & mask[2],
        ip[3] & mask[3],
    };
}

fn maskPrefix(mask: [4]u8) u8 {
    var bits: u8 = 0;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        var byte = mask[i];
        while (byte != 0) : (byte <<= 1) {
            bits += 1;
        }
    }
    return bits;
}

fn cstr(ptr: [*]u8) []const u8 {
    var len: usize = 0;
    while (len < 256) : (len += 1) {
        if (ptr[len] == 0) return ptr[0..len];
    }
    return ptr[0..256];
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn writeIpv4(addr: [4]u8) void {
    var buf: [16]u8 = undefined;
    var pos: usize = 0;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        if (i > 0) {
            buf[pos] = '.';
            pos += 1;
        }
        pos += writeU8Decimal(addr[i], buf[pos..]);
    }
    writeStr(buf[0..pos]);
}

fn writeMac(mac: [6]u8) void {
    const hex = "0123456789abcdef";
    var buf: [18]u8 = undefined;
    var pos: usize = 0;
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        if (i > 0) {
            buf[pos] = ':';
            pos += 1;
        }
        buf[pos] = hex[mac[i] >> 4];
        buf[pos + 1] = hex[mac[i] & 0x0F];
        pos += 2;
    }
    writeStr(buf[0..pos]);
}

fn writeU8Decimal(n: u8, out: []u8) usize {
    if (n >= 100) {
        out[0] = '0' + (n / 100);
        out[1] = '0' + ((n / 10) % 10);
        out[2] = '0' + (n % 10);
        return 3;
    }
    if (n >= 10) {
        out[0] = '0' + (n / 10);
        out[1] = '0' + (n % 10);
        return 2;
    }
    out[0] = '0' + n;
    return 1;
}

fn writeDecimal(n: u8) void {
    var buf: [4]u8 = undefined;
    const len = writeU8Decimal(n, &buf);
    writeStr(buf[0..len]);
}

fn writeStr(s: []const u8) void {
    _ = libc.syscall.write(1, s.ptr, s.len);
}
