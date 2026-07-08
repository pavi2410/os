const argv = @import("../argv.zig");
const cwd = @import("../cwd.zig");
const environ = @import("../environ.zig");
const io = @import("../io.zig");
const path = @import("../path.zig");
const ulib = @import("ulib");

pub fn run(parsed: *const argv.Parsed) u8 {
    const target = parsed.positionalAt(0) orelse "/";

    var pathbuf: [128]u8 = undefined;
    const resolved = path.resolve(target, &pathbuf) orelse {
        io.writeStr("cd: path too long\n");
        return 1;
    };

    var st: ulib.fs.Stat = .{};
    if (ulib.fs.stat(@ptrCast(resolved.ptr), &st) < 0) {
        io.writeStr("cd: not found\n");
        return 1;
    }
    if (!ulib.fs.isDir(st.st_mode)) {
        io.writeStr("cd: not a directory\n");
        return 1;
    }
    if (!cwd.set(resolved)) {
        io.writeStr("cd: path too long\n");
        return 1;
    }
    environ.syncPwd();
    return 0;
}
