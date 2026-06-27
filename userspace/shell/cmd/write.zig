const argv = @import("../argv.zig");
const io = @import("../io.zig");
const path = @import("../path.zig");
const libc = @import("libc");

const O_WRONLY: u32 = 1;
const O_CREAT: u32 = 0o100;
const O_TRUNC: u32 = 0o1000;
const O_APPEND: u32 = 0o2000;

pub fn run(parsed: *const argv.Parsed) void {
    const file_path = parsed.positionalAt(0) orelse {
        io.writeStr("write: usage: write [-a] /path text...\n");
        return;
    };

    var content_buf: [192]u8 = undefined;
    const content = parsed.joinPositionalsFrom(&content_buf, 1) catch {
        io.writeStr("write: text too long\n");
        return;
    };

    writeFile(file_path, content, parsed.hasFlag('a'));
}

fn writeFile(file_path: []const u8, content: []const u8, append: bool) void {
    var pathbuf: [128]u8 = undefined;
    if (!path.copy(file_path, &pathbuf)) {
        io.writeStr("write: path too long\n");
        return;
    }

    var open_flags: u32 = O_WRONLY | O_CREAT;
    if (append) {
        open_flags |= O_APPEND;
    } else {
        open_flags |= O_TRUNC;
    }

    const fd = libc.syscall.open(@ptrCast(&pathbuf), open_flags, 0);
    if (fd < 0) {
        io.writeStr("write: open failed\n");
        return;
    }

    if (content.len > 0) {
        const n = libc.syscall.write(@intCast(fd), content.ptr, content.len);
        if (n < 0) {
            io.writeStr("write: I/O failed\n");
            _ = libc.syscall.close(@intCast(fd));
            return;
        }
    }
    _ = libc.syscall.close(@intCast(fd));
    io.writeStr("write: ok\n");
}
