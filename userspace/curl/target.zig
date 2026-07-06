pub const default_port: u16 = 80;

pub const Target = struct {
    host: []const u8,
    path: []const u8,
    port: u16,
};

pub const ParseError = error{
    BadUrl,
    MissingHost,
    HostTooLong,
    PathTooLong,
};

pub const HostKind = enum {
    ipv4,
    hostname,
};

const http_prefix = "http://";

/// If `input` has no `://` scheme, writes `http://` + input into `norm_buf`.
pub fn normalizeUrl(input: []const u8, norm_buf: []u8) ?[]const u8 {
    if (indexOf(input, "://")) |_| return input;
    if (http_prefix.len + input.len > norm_buf.len) return null;
    @memcpy(norm_buf[0..http_prefix.len], http_prefix);
    @memcpy(norm_buf[http_prefix.len..][0..input.len], input);
    return norm_buf[0 .. http_prefix.len + input.len];
}

pub fn parse(input: []const u8, norm_buf: []u8, host_buf: []u8, path_buf: []u8) ParseError!Target {
    const url_text = normalizeUrl(input, norm_buf) orelse return error.BadUrl;
    if (!startsWith(url_text, http_prefix)) return error.BadUrl;

    const after_scheme = url_text[http_prefix.len..];
    const slash = indexOfScalar(after_scheme, '/');
    const authority = if (slash) |idx| after_scheme[0..idx] else after_scheme;
    const path_src = if (slash) |idx| after_scheme[idx..] else "/";

    if (authority.len == 0) return error.MissingHost;

    var host_len = authority.len;
    var port = default_port;
    if (lastIndexOfScalar(authority, ':')) |colon| {
        const port_text = authority[colon + 1 ..];
        if (port_text.len == 0) return error.BadUrl;
        port = parsePort(port_text) orelse return error.BadUrl;
        host_len = colon;
    }
    if (host_len == 0 or host_len >= host_buf.len) return error.HostTooLong;
    @memcpy(host_buf[0..host_len], authority[0..host_len]);
    const host = host_buf[0..host_len];

    const path = path_slice: {
        if (path_src.len == 0 or eql(path_src, "/")) {
            path_buf[0] = '/';
            break :path_slice path_buf[0..1];
        }
        if (path_src.len > path_buf.len) return error.PathTooLong;
        @memcpy(path_buf[0..path_src.len], path_src);
        break :path_slice path_buf[0..path_src.len];
    };

    return .{ .host = host, .path = path, .port = port };
}

pub fn hostKind(host: []const u8) HostKind {
    var ip: [4]u8 = undefined;
    if (ipv4Bytes(host, &ip)) return .ipv4;
    return .hostname;
}

pub fn ipv4Bytes(host: []const u8, out: *[4]u8) bool {
    var part: u8 = 0;
    var idx: usize = 0;
    var i: usize = 0;
    while (i <= host.len) : (i += 1) {
        if (i == host.len or host[i] == '.') {
            if (idx >= 4) return false;
            out[idx] = part;
            idx += 1;
            part = 0;
            continue;
        }
        const ch = host[i];
        if (ch < '0' or ch > '9') return false;
        const digit: u16 = ch - '0';
        const next = @as(u16, part) * 10 + digit;
        if (next > 255) return false;
        part = @intCast(next);
    }
    return idx == 4;
}

pub fn parsePort(text: []const u8) ?u16 {
    if (text.len == 0 or text.len > 5) return null;
    var value: u16 = 0;
    for (text) |ch| {
        if (ch < '0' or ch > '9') return null;
        const digit: u16 = ch - '0';
        if (value > 6553 or (value == 6553 and digit > 5)) return null;
        value = value * 10 + digit;
    }
    if (value == 0) return null;
    return value;
}

pub fn buildRequest(host: []const u8, path: []const u8, out: []u8) ?usize {
    const prefix = "GET ";
    const mid = " HTTP/1.0\r\nHost: ";
    const suffix = "\r\n\r\n";
    const total = prefix.len + path.len + mid.len + host.len + suffix.len;
    if (total > out.len) return null;
    var off: usize = 0;
    copyInto(out, &off, prefix);
    copyInto(out, &off, path);
    copyInto(out, &off, mid);
    copyInto(out, &off, host);
    copyInto(out, &off, suffix);
    return total;
}

fn copyInto(out: []u8, off: *usize, bytes: []const u8) void {
    @memcpy(out[off.* .. off.* + bytes.len], bytes);
    off.* += bytes.len;
}

pub fn findBodyStart(data: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i + 3 < data.len) : (i += 1) {
        if (data[i] == '\r' and data[i + 1] == '\n' and data[i + 2] == '\r' and data[i + 3] == '\n') {
            return data[i + 4 ..];
        }
    }
    return null;
}

fn indexOf(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or haystack.len < needle.len) return null;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (eql(haystack[i..][0..needle.len], needle)) return i;
    }
    return null;
}

fn indexOfScalar(haystack: []const u8, ch: u8) ?usize {
    for (haystack, 0..) |c, i| {
        if (c == ch) return i;
    }
    return null;
}

fn lastIndexOfScalar(haystack: []const u8, ch: u8) ?usize {
    var i = haystack.len;
    while (i > 0) {
        i -= 1;
        if (haystack[i] == ch) return i;
    }
    return null;
}

fn startsWith(haystack: []const u8, prefix: []const u8) bool {
    return haystack.len >= prefix.len and eql(haystack[0..prefix.len], prefix);
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x != y) return false;
    }
    return true;
}
