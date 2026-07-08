const ulib = @import("ulib");
const common_tap = @import("common/tap");

fn writeLine(s: []const u8) void {
    ulib.io.writeStr(s);
}

pub const Harness = common_tap.Harness(writeLine);
