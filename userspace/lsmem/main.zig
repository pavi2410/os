const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;

const ulib = @import("ulib");

const max_regions = 128;

var regions: [max_regions]ulib.hw.MemRegionInfo = undefined;

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    _ = _argc;
    _ = _argv;

    const n = ulib.hw.getmemregions(&regions, max_regions);
    if (n < 0) {
        writeStr("lsmem: getmemregions failed\n");
        ulib.process.exit(1);
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

        writeStr(ulib.hw.formatHex64(start, &hex));
        writeStr("  ");
        writeStr(ulib.hw.formatHex64(end, &hex));
        writeStr("  ");
        writeStr(ulib.hw.formatSize(length, &size_buf));
        writeStr("  ");
        writeStr(ulib.hw.memKindName(regions[i].kind));
        writeStr("\n");
    }

    ulib.process.exit(0);
}

fn writeStr(s: []const u8) void {
    ulib.io.writeStr(s);
}
