const argv = @import("../argv.zig");
const io = @import("../io.zig");
const path = @import("../path.zig");
const libc = @import("libc");

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
    const resolved = path.resolve(file_path, &pathbuf) orelse {
        io.writeStr("write: path too long\n");
        return;
    };

    var open_flags: u32 = libc.fs.O_WRONLY | libc.fs.O_CREAT;
    if (append) {
        open_flags |= libc.fs.O_APPEND;
    } else {
        open_flags |= libc.fs.O_TRUNC;
    }

    const fd = libc.fs.open(@ptrCast(resolved.ptr), open_flags, 0);
    if (fd < 0) {
        io.writeStr("write: open failed\n");
        return;
    }

    if (content.len > 0) {
        const n = libc.fs.write(@intCast(fd), content.ptr, content.len);
        if (n < 0) {
            io.writeStr("write: I/O failed\n");
            _ = libc.fs.close(@intCast(fd));
            return;
        }
    }
    _ = libc.fs.close(@intCast(fd));
    io.writeStr("write: ok\n");
}
