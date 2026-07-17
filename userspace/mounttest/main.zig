const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = _argc;
    _ = _argv;

    const wflags = ulib.fs.O_RDWR | ulib.fs.O_CREAT | ulib.fs.O_TRUNC;
    const fd = ulib.fs.open("/tmp/mountprobe", wflags, 0);
    if (fd < 0) {
        ulib.io.writeStr("mounttest: create /tmp/mountprobe failed\n");
        return 1;
    }
    _ = ulib.fs.write(@intCast(fd), "alive", 5);
    _ = ulib.fs.close(@intCast(fd));

    if (ulib.fs.umount("/tmp") != 0) {
        ulib.io.writeStr("mounttest: umount /tmp failed\n");
        return 1;
    }

    if (ulib.fs.open("/tmp/mountprobe", ulib.fs.O_RDONLY, 0) >= 0) {
        ulib.io.writeStr("mounttest: file survived umount\n");
        return 1;
    }

    if (ulib.fs.mount(null, "/tmp", "tmpfs", 0, null) != 0) {
        ulib.io.writeStr("mounttest: mount tmpfs failed\n");
        return 1;
    }

    const fd2 = ulib.fs.open("/tmp/fresh", wflags, 0);
    if (fd2 < 0) {
        ulib.io.writeStr("mounttest: create after remount failed\n");
        return 1;
    }
    _ = ulib.fs.close(@intCast(fd2));

    // Remount resets the singleton tmpfs.
    if (ulib.fs.mount(null, "/tmp", "tmpfs", 0, null) != 0) {
        ulib.io.writeStr("mounttest: remount failed\n");
        return 1;
    }
    if (ulib.fs.open("/tmp/fresh", ulib.fs.O_RDONLY, 0) >= 0) {
        ulib.io.writeStr("mounttest: file survived remount\n");
        return 1;
    }

    ulib.io.writeStr("mounttest: ok\n");
    return 0;
}
