const abi_fs = @import("abi_fs");
const filesystem = @import("filesystem.zig");

pub const Device = enum(u8) {
    null_dev = 1,
    zero_dev = 2,
    tty_dev = 3,
};

pub const Node = union(enum) {
    root,
    device: Device,
};

const dev_root_ino: u64 = 1;
const dev_names = [_][]const u8{ "null", "zero", "ttyS0" };
const dev_nodes = [_]Node{
    .{ .device = .null_dev },
    .{ .device = .zero_dev },
    .{ .device = .tty_dev },
};

pub fn lookup(path: []const u8) ?Node {
    if (stdEql(path, "/dev")) return .root;
    if (stdEql(path, "/dev/null")) return .{ .device = .null_dev };
    if (stdEql(path, "/dev/zero")) return .{ .device = .zero_dev };
    if (stdEql(path, "/dev/ttyS0")) return .{ .device = .tty_dev };
    return null;
}

pub fn isDevPath(path: []const u8) bool {
    return path.len >= 4 and path[0] == '/' and stdEql(path[0..4], "/dev") and
        (path.len == 4 or path[4] == '/');
}

pub fn stat(node: Node, out: *filesystem.Stat) void {
    out.* = .{};
    switch (node) {
        .root => {
            out.st_mode = abi_fs.S_IFDIR | 0o755;
            out.st_ino = dev_root_ino;
            out.st_size = 0;
        },
        .device => |dev| {
            out.st_mode = abi_fs.S_IFCHR | 0o666;
            out.st_ino = @intFromEnum(dev);
            out.st_rdev = @intFromEnum(dev);
            out.st_size = 0;
        },
    }
}

pub fn readDevice(dev: Device, buf: []u8) usize {
    return switch (dev) {
        .null_dev => 0,
        .zero_dev => {
            @memset(buf, 0);
            return buf.len;
        },
        .tty_dev => 0,
    };
}

pub fn writeDevice(dev: Device, buf: []const u8) usize {
    _ = dev;
    return buf.len;
}

pub fn getdents64(dir_skip: *usize, buf: []u8) filesystem.Error!usize {
    const total = 2 + dev_names.len;
    if (dir_skip.* >= total) return 0;

    var written: usize = 0;
    var index = dir_skip.*;
    while (index < total) : (index += 1) {
        const name: []const u8 = switch (index) {
            0 => ".",
            1 => "..",
            else => dev_names[index - 2],
        };
        const d_type: u8 = if (index < 2) abi_fs.DT_DIR else abi_fs.DT_CHR;
        const ino: u64 = switch (index) {
            0, 1 => dev_root_ino,
            else => @intFromEnum(dev_nodes[index - 2].device),
        };

        const reclen = abi_fs.dirent64Reclen(name.len);
        if (written + reclen > buf.len) {
            if (written == 0) return filesystem.Error.BufferTooSmall;
            dir_skip.* = index;
            return written;
        }

        abi_fs.writeDirent64(
            buf[written .. written + reclen],
            ino,
            @intCast(index + 1),
            d_type,
            name,
        );
        written += reclen;
    }

    dir_skip.* = total;
    return written;
}

fn stdEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ac, bc| {
        if (ac != bc) return false;
    }
    return true;
}
