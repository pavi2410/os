const argv = @import("../argv.zig");
const environ = @import("../environ.zig");
const io = @import("../io.zig");

pub fn run(parsed: *const argv.Parsed) u8 {
    const line = parsed.positionalAt(0) orelse {
        var i: usize = 0;
        while (i < environ.countEntries()) : (i += 1) {
            io.writeStr(environ.entryAt(i));
            io.writeNewline();
        }
        return 0;
    };

    if (!environ.setLine(line)) {
        io.writeStr("export: invalid assignment\n");
        return 1;
    }
    return 0;
}
