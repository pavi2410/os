const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = _argc;
    _ = _argv;

    var buf: [4096]u8 = undefined;
    const text = readAll("/proc/iomem", &buf) orelse {
        ulib.io.writeStr("lsmem: open /proc/iomem failed\n");
        return 1;
    };

    ulib.io.writeStr("START            END              SIZE             TYPE\n");
    var hex: [16]u8 = undefined;
    var size_buf: [24]u8 = undefined;

    var i: usize = 0;
    while (i < text.len) {
        var line_end = i;
        while (line_end < text.len and text[line_end] != '\n') : (line_end += 1) {}
        const line = text[i..line_end];
        if (line.len > 0) printLine(line, &hex, &size_buf);
        i = if (line_end < text.len) line_end + 1 else text.len;
    }
    return 0;
}

/// Parse `start-end : type` from /proc/iomem.
fn printLine(line: []const u8, hex: *[16]u8, size_buf: *[24]u8) void {
    // Find '-' separating start/end.
    const dash = indexOf(line, '-') orelse return;
    const start = parseHex(line[0..dash]) orelse return;
    var rest = line[dash + 1 ..];
    const colon = indexOf(rest, ':') orelse return;
    // end hex before spaces before ':'
    var end_s = rest[0..colon];
    while (end_s.len > 0 and (end_s[end_s.len - 1] == ' ' or end_s[end_s.len - 1] == '\t')) {
        end_s = end_s[0 .. end_s.len - 1];
    }
    const end = parseHex(end_s) orelse return;
    var type_s = rest[colon + 1 ..];
    while (type_s.len > 0 and (type_s[0] == ' ' or type_s[0] == '\t')) type_s = type_s[1..];
    while (type_s.len > 0 and (type_s[type_s.len - 1] == ' ' or type_s[type_s.len - 1] == '\t' or type_s[type_s.len - 1] == '\r')) {
        type_s = type_s[0 .. type_s.len - 1];
    }

    const length: u64 = if (end >= start) end - start + 1 else 0;

    ulib.io.writeStr(ulib.hw.formatHex64(start, hex));
    ulib.io.writeStr("  ");
    ulib.io.writeStr(ulib.hw.formatHex64(end, hex));
    ulib.io.writeStr("  ");
    ulib.io.writeStr(ulib.hw.formatSize(length, size_buf));
    ulib.io.writeStr("  ");
    ulib.io.writeStr(type_s);
    ulib.io.writeStr("\n");
}

fn readAll(path: [*:0]const u8, buf: []u8) ?[]const u8 {
    const fd = ulib.fs.open(path, ulib.fs.O_RDONLY, 0);
    if (fd < 0) return null;
    defer _ = ulib.fs.close(@intCast(fd));
    var total: usize = 0;
    while (total < buf.len) {
        const n = ulib.fs.read(@intCast(fd), buf[total..].ptr, buf.len - total);
        if (n <= 0) break;
        total += @intCast(n);
    }
    return buf[0..total];
}

fn indexOf(s: []const u8, ch: u8) ?usize {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == ch) return i;
    }
    return null;
}

fn parseHex(s: []const u8) ?u64 {
    if (s.len == 0) return null;
    var v: u64 = 0;
    for (s) |c| {
        const nibble: u64 = if (c >= '0' and c <= '9')
            c - '0'
        else if (c >= 'a' and c <= 'f')
            c - 'a' + 10
        else if (c >= 'A' and c <= 'F')
            c - 'A' + 10
        else
            return null;
        v = (v << 4) | nibble;
    }
    return v;
}
