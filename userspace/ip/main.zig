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

    const sub = libc.io.cstr(argv[1]);
    if (libc.io.eql(sub, "addr") or libc.io.eql(sub, "a")) {
        cmdAddr();
    } else if (libc.io.eql(sub, "route") or libc.io.eql(sub, "r")) {
        cmdRoute();
    } else if (libc.io.eql(sub, "neigh") or libc.io.eql(sub, "n")) {
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
    var cfg: libc.net.NetConfig = undefined;
    if (libc.net.getnetconfig(&cfg) < 0) {
        writeStr("ip: getnetconfig failed\n");
        libc.syscall.exit(1);
    }

    writeStr(iface_name);
    writeStr(": <BROADCAST,MULTICAST,UP> mtu 1500\n");
    writeStr("    inet ");
    writeIpv4(cfg.ip);
    writeStr("/");
    writeDecimal(libc.ip.maskPrefix(cfg.mask));
    writeStr(" scope global ");
    writeStr(iface_name);
    writeStr("\n    link/ether ");
    writeMac(cfg.mac);
    writeStr(" brd ff:ff:ff:ff:ff:ff\n");
}

fn cmdRoute() void {
    var cfg: libc.net.NetConfig = undefined;
    if (libc.net.getnetconfig(&cfg) < 0) {
        writeStr("ip: getnetconfig failed\n");
        libc.syscall.exit(1);
    }

    writeStr("default via ");
    writeIpv4(cfg.gateway);
    writeStr(" dev ");
    writeStr(iface_name);
    writeStr("\n");

    writeStr("network ");
    writeIpv4(libc.ip.networkAddr(cfg.ip, cfg.mask));
    writeStr("/");
    writeDecimal(libc.ip.maskPrefix(cfg.mask));
    writeStr(" dev ");
    writeStr(iface_name);
    writeStr(" scope link\n");
}

fn cmdNeigh() void {
    var entries: [8]libc.net.NeighEntry = undefined;
    const n = libc.net.getneighbors(&entries, entries.len);
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

fn writeIpv4(addr: [4]u8) void {
    var buf: [16]u8 = undefined;
    writeStr(libc.ip.formatIpv4(addr, &buf) orelse "?");
}

fn writeMac(mac: [6]u8) void {
    var buf: [18]u8 = undefined;
    writeStr(libc.ip.formatMac(mac, &buf) orelse "??:??:??:??:??:??");
}

fn writeDecimal(n: u8) void {
    libc.io.writeDecimal(n);
}

fn writeStr(s: []const u8) void {
    libc.io.writeStr(s);
}
