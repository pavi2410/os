const argv = @import("../argv.zig");
const environ = @import("../environ.zig");
const io = @import("../io.zig");

pub fn run(parsed: *const argv.Parsed) u8 {
    const name = parsed.positionalAt(0) orelse {
        io.writeStr("unset: usage: unset NAME\n");
        return 1;
    };

    if (!environ.unset(name)) {
        io.writeStr("unset: not found\n");
        return 1;
    }
    return 0;
}
