const std = @import("std");
const hal = @import("../hal.zig");
const physical = @import("../mm/physical.zig");
const tap_mod = @import("common/tap");
const udp_test = @import("../net/udp_test.zig");
const vfs = @import("../fs/vfs.zig");
const runtime = @import("../runtime.zig");

const Tap = tap_mod.Harness(hal.console.writeAll);

pub fn run() void {
    hal.console.println("\n--- TAP kernel ---", .{});
    Tap.version();
    Tap.plan(3);
    Tap.check("vfs readme read", testVfsReadme());
    Tap.check("udp dns reply", udp_test.dnsReplyOk());
    Tap.check("physical pages free", physical.freePages() >= 64);
    _ = Tap.finish();
    hal.console.println("--- TAP kernel end ---", .{});
}

fn testVfsReadme() bool {
    if (!runtime.boot().vfs.isReady()) return false;

    var buf: [64]u8 = undefined;
    const handle = runtime.boot().vfs.open("/README.TXT", .{}) catch return false;
    defer runtime.boot().vfs.close(handle);

    const n = runtime.boot().vfs.read(handle, &buf) catch return false;
    if (n < 5) return false;
    return std.mem.indexOf(u8, buf[0..n], "Hello") != null;
}
