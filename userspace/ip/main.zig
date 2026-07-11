const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");

const iface_name = "eth0";

export fn main(argc: usize, argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    if (argc < 2) {
        printUsage();
        return 1;
    }

    const sub = ulib.io.cstr(argv[1]);
    if (ulib.string.eql(sub, "addr") or ulib.string.eql(sub, "a")) {
        return cmdAddr();
    }
    if (ulib.string.eql(sub, "route") or ulib.string.eql(sub, "r")) {
        return cmdRoute();
    }
    if (ulib.string.eql(sub, "neigh") or ulib.string.eql(sub, "n")) {
        return cmdNeigh();
    }

    ulib.io.writeStr("ip: unknown subcommand '");
    ulib.io.writeStr(sub);
    ulib.io.writeStr("'\n");
    printUsage();
    return 1;
}

fn printUsage() void {
    ulib.io.writeStr("usage: ip <addr|route|neigh>\n");
}

fn cmdAddr() u8 {
    var cfg: ulib.net.NetConfig = undefined;
    if (ulib.net.getnetconfig(&cfg) < 0) {
        ulib.io.writeStr("ip: getnetconfig failed\n");
        return 1;
    }

    ulib.io.writeStr(iface_name);
    ulib.io.writeStr(": <BROADCAST,MULTICAST,UP> mtu 1500\n");
    ulib.io.writeStr("    inet ");
    writeIpv4(cfg.ip);
    ulib.io.writeStr("/");
    ulib.io.writeDecimal(ulib.ip.maskPrefix(cfg.mask));
    ulib.io.writeStr(" scope global ");
    ulib.io.writeStr(iface_name);
    ulib.io.writeStr("\n    link/ether ");
    writeMac(cfg.mac);
    ulib.io.writeStr(" brd ff:ff:ff:ff:ff:ff\n");
    return 0;
}

fn cmdRoute() u8 {
    var cfg: ulib.net.NetConfig = undefined;
    if (ulib.net.getnetconfig(&cfg) < 0) {
        ulib.io.writeStr("ip: getnetconfig failed\n");
        return 1;
    }

    ulib.io.writeStr("default via ");
    writeIpv4(cfg.gateway);
    ulib.io.writeStr(" dev ");
    ulib.io.writeStr(iface_name);
    ulib.io.writeStr("\n");

    ulib.io.writeStr("network ");
    writeIpv4(ulib.ip.networkAddr(cfg.ip, cfg.mask));
    ulib.io.writeStr("/");
    ulib.io.writeDecimal(ulib.ip.maskPrefix(cfg.mask));
    ulib.io.writeStr(" dev ");
    ulib.io.writeStr(iface_name);
    ulib.io.writeStr(" scope link\n");
    return 0;
}

fn cmdNeigh() u8 {
    var entries: [8]ulib.net.NeighEntry = undefined;
    const n = ulib.net.getneighbors(&entries, entries.len);
    if (n < 0) {
        ulib.io.writeStr("ip: getneighbors failed\n");
        return 1;
    }

    var i: usize = 0;
    while (i < @as(usize, @intCast(n))) : (i += 1) {
        writeIpv4(entries[i].ip);
        ulib.io.writeStr(" dev ");
        ulib.io.writeStr(iface_name);
        ulib.io.writeStr(" lladdr ");
        writeMac(entries[i].mac);
        ulib.io.writeStr(" REACHABLE\n");
    }
    return 0;
}

fn writeIpv4(addr: [4]u8) void {
    var buf: [16]u8 = undefined;
    ulib.io.writeStr(ulib.ip.formatIpv4(addr, &buf) orelse "?");
}

fn writeMac(mac: [6]u8) void {
    var buf: [18]u8 = undefined;
    ulib.io.writeStr(ulib.ip.formatMac(mac, &buf) orelse "??:??:??:??:??:??");
}
