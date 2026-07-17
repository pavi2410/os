const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = _argc;
    _ = _argv;

    const wflags = ulib.fs.O_RDWR | ulib.fs.O_CREAT | ulib.fs.O_TRUNC;
    const fd = ulib.fs.open("/LINKOLD.TXT", wflags, 0);
    if (fd < 0) {
        ulib.io.writeStr("linktest: create LINKOLD failed\n");
        return 1;
    }
    _ = ulib.fs.write(@intCast(fd), "renamed", 7);
    _ = ulib.fs.close(@intCast(fd));

    if (ulib.fs.rename("/LINKOLD.TXT", "/LINKNEW.TXT") != 0) {
        ulib.io.writeStr("linktest: fat rename failed\n");
        return 1;
    }
    if (ulib.fs.open("/LINKOLD.TXT", ulib.fs.O_RDONLY, 0) >= 0) {
        ulib.io.writeStr("linktest: old fat name still exists\n");
        return 1;
    }
    const fd2 = ulib.fs.open("/LINKNEW.TXT", ulib.fs.O_RDONLY, 0);
    if (fd2 < 0) {
        ulib.io.writeStr("linktest: new fat name missing\n");
        return 1;
    }
    _ = ulib.fs.close(@intCast(fd2));
    _ = ulib.fs.unlink("/LINKNEW.TXT");

    if (ulib.fs.symlink("/tmp/target", "/tmp/mylink") != 0) {
        ulib.io.writeStr("linktest: symlink failed\n");
        return 1;
    }
    var buf: [64]u8 = undefined;
    const n = ulib.fs.readlink("/tmp/mylink", &buf, buf.len);
    if (n < 0) {
        ulib.io.writeStr("linktest: readlink failed\n");
        return 1;
    }
    if (n != 11 or !bytesEql(buf[0..@intCast(n)], "/tmp/target")) {
        ulib.io.writeStr("linktest: readlink mismatch\n");
        return 1;
    }

    if (ulib.fs.rename("/tmp/mylink", "/tmp/otherlink") != 0) {
        ulib.io.writeStr("linktest: tmpfs rename failed\n");
        return 1;
    }
    const n2 = ulib.fs.readlink("/tmp/otherlink", &buf, buf.len);
    if (n2 != 11) {
        ulib.io.writeStr("linktest: renamed link broken\n");
        return 1;
    }

    // FAT does not support symlinks.
    if (ulib.fs.symlink("x", "/FATLINK.TXT") == 0) {
        ulib.io.writeStr("linktest: fat symlink should fail\n");
        return 1;
    }

    ulib.io.writeStr("linktest: ok\n");
    return 0;
}

fn bytesEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (x != y) return false;
    return true;
}
