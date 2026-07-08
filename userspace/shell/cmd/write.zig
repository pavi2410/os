const argv = @import("../argv.zig");
const io = @import("../io.zig");
const path = @import("../path.zig");
const ulib = @import("ulib");

pub fn run(parsed: *const argv.Parsed) u8 {
    const file_path = parsed.positionalAt(0) orelse {
        io.writeStr("write: usage: write [-a] /path text...\n");
        return 1;
    };

    var content_buf: [192]u8 = undefined;
    const content = parsed.joinPositionalsFrom(&content_buf, 1) catch {
        io.writeStr("write: text too long\n");
        return 1;
    };

    return writeFile(file_path, content, parsed.hasFlag('a'));
}

fn writeFile(file_path: []const u8, content: []const u8, append: bool) u8 {
    var pathbuf: [128]u8 = undefined;
    const resolved = path.resolve(file_path, &pathbuf) orelse {
        io.writeStr("write: path too long\n");
        return 1;
    };

    var open_flags: u32 = ulib.fs.O_WRONLY | ulib.fs.O_CREAT;
    if (append) {
        open_flags |= ulib.fs.O_APPEND;
    } else {
        open_flags |= ulib.fs.O_TRUNC;
    }

    const fd = ulib.fs.open(@ptrCast(resolved.ptr), open_flags, 0);
    if (fd < 0) {
        io.writeStr("write: open failed\n");
        return 1;
    }

    if (content.len > 0) {
        const n = ulib.fs.write(@intCast(fd), content.ptr, content.len);
        if (n < 0) {
            io.writeStr("write: I/O failed\n");
            _ = ulib.fs.close(@intCast(fd));
            return 1;
        }
    }
    _ = ulib.fs.close(@intCast(fd));
    io.writeStr("write: ok\n");
    return 0;
}
