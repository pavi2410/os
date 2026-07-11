const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = _argc;
    _ = _argv;

    const null_fd = ulib.fs.open("/dev/null", ulib.fs.O_RDWR, 0);
    if (null_fd < 0) {
        ulib.io.writeStr("devtest: open /dev/null failed\n");
        return 1;
    }

    const payload = "ignored";
    if (ulib.fs.write(@intCast(null_fd), payload.ptr, payload.len) != @as(i64, @intCast(payload.len))) {
        ulib.io.writeStr("devtest: write /dev/null failed\n");
        return 1;
    }

    var buf: [8]u8 = .{0xAA} ** 8;
    const read_len = ulib.fs.read(@intCast(null_fd), &buf, buf.len);
    if (read_len != 0) {
        ulib.io.writeStr("devtest: read /dev/null expected eof\n");
        return 1;
    }
    _ = ulib.fs.close(@intCast(null_fd));

    const zero_fd = ulib.fs.open("/dev/zero", ulib.fs.O_RDONLY, 0);
    if (zero_fd < 0) {
        ulib.io.writeStr("devtest: open /dev/zero failed\n");
        return 1;
    }

    var zero_buf: [4]u8 = .{0xFF} ** 4;
    if (ulib.fs.read(@intCast(zero_fd), &zero_buf, zero_buf.len) != @as(i64, @intCast(zero_buf.len))) {
        ulib.io.writeStr("devtest: read /dev/zero failed\n");
        return 1;
    }
    if (zero_buf[0] != 0 or zero_buf[3] != 0) {
        ulib.io.writeStr("devtest: /dev/zero not zero-filled\n");
        return 1;
    }
    _ = ulib.fs.close(@intCast(zero_fd));

    ulib.io.writeStr("devtest: ok\n");
    return 0;
}
