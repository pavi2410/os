const freestanding_std = @import("freestanding_std");
const libc = @import("libc");

pub const std_options_debug_io = freestanding_std.std_options_debug_io;
pub const std_options = freestanding_std.std_options;

const max_regions = 128;

var regions: [max_regions]libc.hw.MemRegionInfo = undefined;

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    _ = _argc;
    _ = _argv;

    const n = libc.hw.getmemregions(&regions, max_regions);
    if (n < 0) {
        writeStr("lsmem: getmemregions failed\n");
        libc.process.exit(1);
    }

    const count = @min(@as(usize, @intCast(n)), max_regions);
    writeStr("START            END              SIZE             TYPE\n");
    var hex: [16]u8 = undefined;
    var size_buf: [24]u8 = undefined;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const start = regions[i].start;
        const length = regions[i].length;
        const end = if (length > 0) start + length - 1 else start;

        writeStr(libc.hw.formatHex64(start, &hex));
        writeStr("  ");
        writeStr(libc.hw.formatHex64(end, &hex));
        writeStr("  ");
        writeStr(libc.hw.formatSize(length, &size_buf));
        writeStr("  ");
        writeStr(libc.hw.memKindName(regions[i].kind));
        writeStr("\n");
    }

    libc.process.exit(0);
}

fn writeStr(s: []const u8) void {
    libc.io.writeStr(s);
}
