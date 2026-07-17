const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = _argc;
    _ = _argv;

    var buf: [1024]u8 = undefined;
    const text = readAll("/proc/cpuinfo", &buf) orelse {
        ulib.io.writeStr("lscpu: open /proc/cpuinfo failed\n");
        return 1;
    };

    ulib.io.writeStr("Architecture:        x86_64\n");
    writeField("Vendor ID:           ", lookup(text, "vendor_id"));
    writeField("CPU family:          ", lookup(text, "cpu family"));
    writeField("Model:               ", lookup(text, "model"));
    writeField("Stepping:            ", lookup(text, "stepping"));
    writeField("Model name:          ", lookup(text, "model name"));
    writeField("APIC ID:             ", lookup(text, "apic_id"));
    writeField("CPU(s):              ", lookup(text, "cpu cores"));
    writeField("IOAPIC count:        ", lookup(text, "ioapic_count"));
    return 0;
}

fn writeField(label: []const u8, value: ?[]const u8) void {
    ulib.io.writeStr(label);
    if (value) |v| ulib.io.writeStr(v);
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

fn lookup(text: []const u8, key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < text.len) {
        var line_end = i;
        while (line_end < text.len and text[line_end] != '\n') : (line_end += 1) {}
        const line = text[i..line_end];
        if (matchKey(line, key)) |value| return trim(value);
        i = if (line_end < text.len) line_end + 1 else text.len;
    }
    return null;
}

fn matchKey(line: []const u8, key: []const u8) ?[]const u8 {
    if (line.len < key.len) return null;
    if (!eql(line[0..key.len], key)) return null;
    var j = key.len;
    while (j < line.len and (line[j] == ' ' or line[j] == '\t')) : (j += 1) {}
    if (j >= line.len or line[j] != ':') return null;
    j += 1;
    while (j < line.len and (line[j] == ' ' or line[j] == '\t')) : (j += 1) {}
    return line[j..];
}

fn trim(s: []const u8) []const u8 {
    var end = s.len;
    while (end > 0 and (s[end - 1] == ' ' or s[end - 1] == '\t' or s[end - 1] == '\r')) : (end -= 1) {}
    return s[0..end];
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}
