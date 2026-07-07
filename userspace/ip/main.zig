const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;

const ulib = @import("ulib");

const iface_name = "eth0";

export fn main(argc: usize, argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    if (argc < 2) {
        printUsage();
        ulib.process.exit(1);
    }

    const sub = ulib.io.cstr(argv[1]);
    if (ulib.io.eql(sub, "addr") or ulib.io.eql(sub, "a")) {
        cmdAddr();
    } else if (ulib.io.eql(sub, "route") or ulib.io.eql(sub, "r")) {
        cmdRoute();
    } else if (ulib.io.eql(sub, "neigh") or ulib.io.eql(sub, "n")) {
        cmdNeigh();
    } else {
        writeStr("ip: unknown subcommand '");
        writeStr(sub);
        writeStr("'\n");
        printUsage();
        ulib.process.exit(1);
    }

    ulib.process.exit(0);
}

fn printUsage() void {
    writeStr("usage: ip <addr|route|neigh>\n");
}

fn cmdAddr() void {
    var cfg: ulib.net.NetConfig = undefined;
    if (ulib.net.getnetconfig(&cfg) < 0) {
        writeStr("ip: getnetconfig failed\n");
        ulib.process.exit(1);
    }

    writeStr(iface_name);
    writeStr(": <BROADCAST,MULTICAST,UP> mtu 1500\n");
    writeStr("    inet ");
    writeIpv4(cfg.ip);
    writeStr("/");
    ulib.io.writeDecimal(ulib.ip.maskPrefix(cfg.mask));
    writeStr(" scope global ");
    writeStr(iface_name);
    writeStr("\n    link/ether ");
    writeMac(cfg.mac);
    writeStr(" brd ff:ff:ff:ff:ff:ff\n");
}

fn cmdRoute() void {
    var cfg: ulib.net.NetConfig = undefined;
    if (ulib.net.getnetconfig(&cfg) < 0) {
        writeStr("ip: getnetconfig failed\n");
        ulib.process.exit(1);
    }

    writeStr("default via ");
    writeIpv4(cfg.gateway);
    writeStr(" dev ");
    writeStr(iface_name);
    writeStr("\n");

    writeStr("network ");
    writeIpv4(ulib.ip.networkAddr(cfg.ip, cfg.mask));
    writeStr("/");
    ulib.io.writeDecimal(ulib.ip.maskPrefix(cfg.mask));
    writeStr(" dev ");
    writeStr(iface_name);
    writeStr(" scope link\n");
}

fn cmdNeigh() void {
    var entries: [8]ulib.net.NeighEntry = undefined;
    const n = ulib.net.getneighbors(&entries, entries.len);
    if (n < 0) {
        writeStr("ip: getneighbors failed\n");
        ulib.process.exit(1);
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

fn writeIpv4(addr: [4]u8) void {
    var buf: [16]u8 = undefined;
    writeStr(ulib.ip.formatIpv4(addr, &buf) orelse "?");
}

fn writeMac(mac: [6]u8) void {
    var buf: [18]u8 = undefined;
    writeStr(ulib.ip.formatMac(mac, &buf) orelse "??:??:??:??:??:??");
}

fn writeStr(s: []const u8) void {
    ulib.io.writeStr(s);
}
