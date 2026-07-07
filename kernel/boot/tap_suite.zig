const hal = @import("../hal.zig");
const physical = @import("../mm/physical.zig");
const tap_mod = @import("common_tap");
const udp_test = @import("../net/udp_test.zig");
const vfs = @import("../fs/vfs.zig");

const Tap = tap_mod.Harness(hal.console.writeString);

pub fn run() void {
    hal.console.writeString("\r\n--- TAP kernel ---\r\n");
    Tap.version();
    Tap.plan(3);
    Tap.check("vfs readme read", testVfsReadme());
    Tap.check("udp dns reply", udp_test.dnsReplyOk());
    Tap.check("physical pages free", physical.freePages() > 0);
    _ = Tap.finish();
    hal.console.writeString("--- TAP kernel end ---\r\n");
}

fn testVfsReadme() bool {
    if (!vfs.isReady()) return false;

    var buf: [64]u8 = undefined;
    const handle = vfs.open("/README.TXT", .{}) catch return false;
    defer vfs.close(handle);

    const n = vfs.read(handle, &buf) catch return false;
    return n > 0;
}
