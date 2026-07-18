const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");

const reset = "\x1b[0m";
const bold = "\x1b[1m";
const cyan = "\x1b[36m";
const blue = "\x1b[34m";
const white = "\x1b[37m";

const logo = [_][]const u8{
    "        ___  ___  ",
    "       / _ \\/ __| ",
    "      | (_) \\__ \\ ",
    "       \\___/|___/ ",
    "                  ",
    "     hobby x86-64 ",
    "                  ",
    "                  ",
};

const logo_width: usize = 18;
const gap = "  ";

const InfoLine = struct {
    key: []const u8,
    value: []const u8,
};

export fn main(argc: usize, argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    var cpu_buf: [1024]u8 = undefined;
    var mem_buf: [4096]u8 = undefined;
    var uptime_buf: [48]u8 = undefined;
    var mem_out: [32]u8 = undefined;

    const cpu_text = readAll("/proc/cpuinfo", &cpu_buf);
    const mem_text = readAll("/proc/iomem", &mem_buf);

    const host = ulib.environ.getenv("HOSTNAME", argc, @ptrCast(argv)) orelse "localhost";
    const shell = ulib.environ.getenv("SHELL", argc, @ptrCast(argv)) orelse "/BIN/SHELL";

    var cpu_value: []const u8 = "unknown";
    if (cpu_text) |text| {
        if (lookup(text, "model name")) |name| {
            cpu_value = name;
        } else if (lookup(text, "vendor_id")) |vendor| {
            cpu_value = vendor;
        }
    }

    const mem_bytes = if (mem_text) |text| sumConventional(text) else 0;
    const mem_value = formatMib(mem_bytes, &mem_out);

    const uptime_value = formatUptime(&uptime_buf);

    const infos = [_]InfoLine{
        .{ .key = "OS", .value = "os x86_64" },
        .{ .key = "Host", .value = host },
        .{ .key = "Uptime", .value = uptime_value },
        .{ .key = "Shell", .value = shell },
        .{ .key = "CPU", .value = cpu_value },
        .{ .key = "Memory", .value = mem_value },
        .{ .key = "Terminal", .value = "serial" },
    };

    const rows = if (logo.len > infos.len) logo.len else infos.len;
    var i: usize = 0;
    while (i < rows) : (i += 1) {
        if (i < logo.len) {
            ulib.io.writeStr(cyan);
            ulib.io.writeStr(logo[i]);
            ulib.io.writeStr(reset);
            // logo lines are already logo_width; no extra pad needed.
        } else {
            writeSpaces(logo_width);
        }
        ulib.io.writeStr(gap);
        if (i < infos.len) {
            ulib.io.writeStr(bold);
            ulib.io.writeStr(blue);
            ulib.io.writeStr(infos[i].key);
            ulib.io.writeStr(": ");
            ulib.io.writeStr(reset);
            ulib.io.writeStr(white);
            ulib.io.writeStr(infos[i].value);
            ulib.io.writeStr(reset);
        }
        ulib.io.writeStr("\n");
    }

    writeSpaces(logo_width);
    ulib.io.writeStr(gap);
    writePalette();
    ulib.io.writeStr("\n");
    return 0;
}

fn writePalette() void {
    // Dark then bright 8-color blocks (classic neofetch).
    var c: u8 = 0;
    while (c < 8) : (c += 1) {
        writeColorBlock(40 + c);
    }
    ulib.io.writeStr(" ");
    c = 0;
    while (c < 8) : (c += 1) {
        writeColorBlock(100 + c);
    }
    ulib.io.writeStr(reset);
}

fn writeColorBlock(code: u8) void {
    ulib.io.writeStr("\x1b[");
    ulib.io.writeU8(code);
    ulib.io.writeStr("m   ");
}

fn writeSpaces(n: usize) void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        ulib.io.writeChar(' ');
    }
}

fn formatUptime(out: []u8) []const u8 {
    var ts: ulib.time.Timespec = undefined;
    if (!ulib.time.monotonic(&ts)) return "unknown";
    if (ts.tv_sec < 0) return "unknown";
    var secs: u64 = @intCast(ts.tv_sec);

    const days = secs / 86400;
    secs %= 86400;
    const hours = secs / 3600;
    secs %= 3600;
    const mins = secs / 60;

    var len: usize = 0;
    if (days > 0) {
        len = appendU64(out, len, days);
        len = appendStr(out, len, "d ");
    }
    if (days > 0 or hours > 0) {
        len = appendU64(out, len, hours);
        len = appendStr(out, len, "h ");
    }
    len = appendU64(out, len, mins);
    len = appendStr(out, len, "m");
    return out[0..len];
}

fn formatMib(bytes: u64, out: []u8) []const u8 {
    const mib = bytes / (1024 * 1024);
    var len: usize = 0;
    len = appendU64(out, len, mib);
    len = appendStr(out, len, " MiB");
    return out[0..len];
}

fn appendU64(out: []u8, start: usize, n: u64) usize {
    var buf: [20]u8 = undefined;
    var v = n;
    var dcount: usize = 0;
    if (v == 0) {
        buf[0] = '0';
        dcount = 1;
    } else {
        while (v > 0) : (v /= 10) {
            buf[dcount] = @truncate((v % 10) + '0');
            dcount += 1;
        }
    }
    var len = start;
    while (dcount > 0) : (dcount -= 1) {
        if (len >= out.len) return len;
        out[len] = buf[dcount - 1];
        len += 1;
    }
    return len;
}

fn appendStr(out: []u8, start: usize, s: []const u8) usize {
    if (start + s.len > out.len) return start;
    @memcpy(out[start .. start + s.len], s);
    return start + s.len;
}

fn sumConventional(text: []const u8) u64 {
    var total: u64 = 0;
    var i: usize = 0;
    while (i < text.len) {
        var line_end = i;
        while (line_end < text.len and text[line_end] != '\n') : (line_end += 1) {}
        const line = text[i..line_end];
        if (conventionalSize(line)) |sz| total += sz;
        i = if (line_end < text.len) line_end + 1 else text.len;
    }
    return total;
}

/// Parse `start-end : type` and return length if type is conventional.
fn conventionalSize(line: []const u8) ?u64 {
    const dash = indexOf(line, '-') orelse return null;
    const start = parseHex(line[0..dash]) orelse return null;
    var rest = line[dash + 1 ..];
    const colon = indexOf(rest, ':') orelse return null;
    var end_s = rest[0..colon];
    while (end_s.len > 0 and (end_s[end_s.len - 1] == ' ' or end_s[end_s.len - 1] == '\t')) {
        end_s = end_s[0 .. end_s.len - 1];
    }
    const end = parseHex(end_s) orelse return null;
    var type_s = rest[colon + 1 ..];
    while (type_s.len > 0 and (type_s[0] == ' ' or type_s[0] == '\t')) type_s = type_s[1..];
    while (type_s.len > 0 and (type_s[type_s.len - 1] == ' ' or type_s[type_s.len - 1] == '\t' or type_s[type_s.len - 1] == '\r')) {
        type_s = type_s[0 .. type_s.len - 1];
    }
    if (!eql(type_s, "conventional")) return null;
    if (end < start) return null;
    return end - start + 1;
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

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}
