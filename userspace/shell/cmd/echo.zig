const argv = @import("../argv.zig");
const io = @import("../io.zig");

pub fn run(parsed: *const argv.Parsed) u8 {
    if (parsed.positionalAt(0) == null) {
        io.writeNewline();
        return 0;
    }

    var buf: [192]u8 = undefined;
    const text = parsed.joinPositionalsFrom(&buf, 0) catch {
        io.writeStr("echo: text too long\n");
        return 1;
    };
    io.writeStr(text);
    io.writeNewline();
    return 0;
}
