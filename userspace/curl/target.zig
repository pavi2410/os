const ulib = @import("ulib");

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
    if (ulib.string.indexOf(input, "://")) |_| return input;
    if (http_prefix.len + input.len > norm_buf.len) return null;
    @memcpy(norm_buf[0..http_prefix.len], http_prefix);
    @memcpy(norm_buf[http_prefix.len..][0..input.len], input);
    return norm_buf[0 .. http_prefix.len + input.len];
}

pub fn parse(input: []const u8, norm_buf: []u8, host_buf: []u8, path_buf: []u8) ParseError!Target {
    const url_text = normalizeUrl(input, norm_buf) orelse return error.BadUrl;
    if (!ulib.string.startsWith(url_text, http_prefix)) return error.BadUrl;

    const after_scheme = url_text[http_prefix.len..];
    const slash = ulib.string.indexOfScalar(after_scheme, '/');
    const authority = if (slash) |idx| after_scheme[0..idx] else after_scheme;
    const path_src = if (slash) |idx| after_scheme[idx..] else "/";

    if (authority.len == 0) return error.MissingHost;

    var host_len = authority.len;
    var port = default_port;
    if (ulib.string.lastIndexOfScalar(authority, ':')) |colon| {
        const port_text = authority[colon + 1 ..];
        if (port_text.len == 0) return error.BadUrl;
        port = ulib.parse.parsePort(port_text) orelse return error.BadUrl;
        host_len = colon;
    }
    if (host_len == 0 or host_len >= host_buf.len) return error.HostTooLong;
    @memcpy(host_buf[0..host_len], authority[0..host_len]);
    const host = host_buf[0..host_len];

    const path = path_slice: {
        if (path_src.len == 0 or ulib.string.eql(path_src, "/")) {
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
    var addr: [4]u8 = undefined;
    if (ulib.ip.parseIpv4(host, &addr)) return .ipv4;
    return .hostname;
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
