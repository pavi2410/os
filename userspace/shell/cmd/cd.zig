const argv = @import("../argv.zig");
const cwd = @import("../cwd.zig");
const io = @import("../io.zig");
const path = @import("../path.zig");
const libc = @import("libc");

pub fn run(parsed: *const argv.Parsed) void {
    const target = parsed.positionalAt(0) orelse "/";

    var pathbuf: [128]u8 = undefined;
    const resolved = path.resolve(target, &pathbuf) orelse {
        io.writeStr("cd: path too long\n");
        return;
    };

    var st: libc.fs.Stat = .{};
    if (libc.fs.stat(@ptrCast(resolved.ptr), &st) < 0) {
        io.writeStr("cd: not found\n");
        return;
    }
    if (!libc.fs.isDir(st.st_mode)) {
        io.writeStr("cd: not a directory\n");
        return;
    }
    if (!cwd.set(resolved)) {
        io.writeStr("cd: path too long\n");
        return;
    }
}
