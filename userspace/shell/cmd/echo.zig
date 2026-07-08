const argv = @import("../argv.zig");
const expand = @import("../expand.zig");
const io = @import("../io.zig");

pub fn run(parsed: *const argv.Parsed) void {
    if (parsed.positionalAt(0) == null) {
        io.writeNewline();
        return;
    }

    var raw: [192]u8 = undefined;
    const joined = parsed.joinPositionalsFrom(&raw, 0) catch {
        io.writeStr("echo: text too long\n");
        return;
    };

    var expanded: [256]u8 = undefined;
    const text = expand.expand(joined, &expanded) orelse {
        io.writeStr("echo: text too long\n");
        return;
    };
    io.writeStr(text);
    io.writeNewline();
}
