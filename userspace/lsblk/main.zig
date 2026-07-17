const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = _argc;
    _ = _argv;

    const fd = ulib.fs.open("/sys/block", ulib.fs.O_RDONLY, 0);
    if (fd < 0) {
        ulib.io.writeStr("lsblk: open /sys/block failed\n");
        return 1;
    }
    defer _ = ulib.fs.close(@intCast(fd));

    ulib.io.writeStr("NAME             SIZE\n");

    var dent_buf: [512]u8 = undefined;
    while (true) {
        const n = ulib.fs.getdents64(@intCast(fd), &dent_buf, dent_buf.len);
        if (n <= 0) break;
        var it = ulib.fs.Dirent64Iterator{ .data = dent_buf[0..@intCast(n)] };
        while (it.next()) |ent| {
            if (ent.name.len == 0 or ent.name[0] == '.') continue;
            printBlock(ent.name);
        }
    }
    return 0;
}

fn printBlock(name: []const u8) void {
    var path_buf: [64]u8 = undefined;
    var size_buf: [32]u8 = undefined;
    var sect_buf: [32]u8 = undefined;

    const size_s = readAttr(name, "size", &path_buf, &size_buf) orelse return;
    const sect_s = readAttr(name, "sector_size", &path_buf, &sect_buf) orelse return;
    const sectors = parseU64(trimNl(size_s)) orelse return;
    const sector_size = parseU64(trimNl(sect_s)) orelse return;

    ulib.io.writeStr(name);
    var pad: usize = 17;
    if (name.len < 17) pad = 17 - name.len;
    while (pad > 0) : (pad -= 1) ulib.io.writeStr(" ");

    if (sector_size == 0) {
        ulib.io.writeStr("0B\n");
        return;
    }
    const bytes = blockBytes(sectors, @intCast(sector_size));
    var out: [32]u8 = undefined;
    ulib.io.writeStr(ulib.hw.formatSize(bytes, &out));
    ulib.io.writeStr("\n");
}

fn readAttr(name: []const u8, attr: []const u8, path_buf: []u8, out: []u8) ?[]const u8 {
    const prefix = "/sys/block/";
    if (prefix.len + name.len + 1 + attr.len + 1 > path_buf.len) return null;
    var p: usize = 0;
    @memcpy(path_buf[p .. p + prefix.len], prefix);
    p += prefix.len;
    @memcpy(path_buf[p .. p + name.len], name);
    p += name.len;
    path_buf[p] = '/';
    p += 1;
    @memcpy(path_buf[p .. p + attr.len], attr);
    p += attr.len;
    path_buf[p] = 0;

    const fd = ulib.fs.open(@ptrCast(path_buf.ptr), ulib.fs.O_RDONLY, 0);
    if (fd < 0) return null;
    defer _ = ulib.fs.close(@intCast(fd));
    const n = ulib.fs.read(@intCast(fd), out.ptr, out.len);
    if (n <= 0) return null;
    return out[0..@intCast(n)];
}

fn trimNl(s: []const u8) []const u8 {
    var end = s.len;
    while (end > 0 and (s[end - 1] == '\n' or s[end - 1] == '\r' or s[end - 1] == ' ')) : (end -= 1) {}
    return s[0..end];
}

fn parseU64(s: []const u8) ?u64 {
    if (s.len == 0) return null;
    var v: u64 = 0;
    for (s) |c| {
        if (c < '0' or c > '9') return null;
        v = v * 10 + (c - '0');
    }
    return v;
}

fn blockBytes(capacity_sectors: u64, sector_size: u32) u64 {
    const wide = @as(u64, sector_size);
    const product, const overflow = @mulWithOverflow(capacity_sectors, wide);
    return if (overflow != 0) 0 else product;
}
