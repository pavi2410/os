const std = @import("std");
const argv = @import("../argv.zig");
const cwd = @import("../cwd.zig");
const io = @import("../io.zig");
const path = @import("../path.zig");
const ulib = @import("ulib");

pub fn run(parsed: *const argv.Parsed) u8 {
    const dir_arg = parsed.positionalAt(0);
    return lsDir(dir_arg, parsed.hasFlag('l'));
}

fn lsDir(dir_arg: ?[]const u8, long: bool) u8 {
    var pathbuf: [128]u8 = undefined;
    const input = dir_arg orelse cwd.get();
    const dir = path.resolve(input, &pathbuf) orelse {
        io.writeStr("ls: path too long\n");
        return 1;
    };

    var st: ulib.fs.Stat = .{};
    if (ulib.fs.stat(@ptrCast(dir.ptr), &st) < 0) {
        io.writeStr("ls: failed\n");
        return 1;
    }
    if (!ulib.fs.isDir(st.st_mode)) {
        io.writeStr("ls: not a directory\n");
        return 1;
    }

    const fd = ulib.fs.open(@ptrCast(dir.ptr), ulib.fs.O_RDONLY, 0);
    if (fd < 0) {
        io.writeStr("ls: failed\n");
        return 1;
    }
    defer _ = ulib.fs.close(@intCast(fd));

    var buf: [1024]u8 = undefined;
    while (true) {
        const n = ulib.fs.getdents64(@intCast(fd), &buf, buf.len);
        if (n <= 0) break;
        if (long) {
            emitLongNames(dir, buf[0..@intCast(n)]);
        } else {
            emitShortNames(buf[0..@intCast(n)]);
        }
    }
    return 0;
}

fn emitShortNames(data: []const u8) void {
    var it = ulib.fs.Dirent64Iterator{ .data = data };
    while (it.next()) |entry| {
        if (!shouldShow(entry.name)) continue;
        io.writeStr(entry.name);
        io.writeNewline();
    }
}

fn emitLongNames(dir: []const u8, data: []const u8) void {
    var it = ulib.fs.Dirent64Iterator{ .data = data };
    while (it.next()) |entry| {
        if (!shouldShow(entry.name)) continue;
        printLongEntry(dir, entry.name);
    }
}

fn shouldShow(name: []const u8) bool {
    return name.len > 0 and !io.eql(name, ".") and !io.eql(name, "..");
}

fn printLongEntry(dir: []const u8, name: []const u8) void {
    var pathbuf: [128]u8 = undefined;
    if (!path.join(dir, name, &pathbuf)) return;

    var st: ulib.fs.Stat = .{};
    if (ulib.fs.stat(@ptrCast(&pathbuf), &st) < 0) return;

    writeEntryType(st.st_mode);
    printSizePadded(@intCast(@max(st.st_size, 0)));
    io.writeStr(" ");
    io.writeStr(name);
    io.writeNewline();
}

fn writeEntryType(mode: u32) void {
    switch (ulib.fs.ModeType.fromMode(mode) orelse {
        io.writeStr("file ");
        return;
    }) {
        .chr => io.writeStr("cdev "),
        .dir => io.writeStr("dir  "),
        .reg, .lnk => io.writeStr("file "),
    }
}

fn printSizePadded(value: u64) void {
    var buf: [16]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{d:>8}", .{value}) catch return;
    io.writeStr(out);
}
