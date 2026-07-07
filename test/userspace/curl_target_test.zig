const std = @import("std");
const target = @import("curl_target");

test "normalizeUrl prepends http for bare hosts" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("http://10.0.2.2", target.normalizeUrl("10.0.2.2", &buf).?);
    try std.testing.expectEqualStrings("http://example.com", target.normalizeUrl("example.com", &buf).?);
    try std.testing.expectEqualStrings("http://10.0.2.2:8080", target.normalizeUrl("10.0.2.2:8080", &buf).?);
}

test "normalizeUrl leaves explicit schemes untouched" {
    var buf: [64]u8 = undefined;
    const url = "http://example.com/foo";
    try std.testing.expectEqualStrings(url, target.normalizeUrl(url, &buf).?);
}

test "parse accepts bare IPv4" {
    var norm: [256]u8 = undefined;
    var host: [128]u8 = undefined;
    var path: [128]u8 = undefined;
    const got = try target.parse("10.0.2.2", &norm, &host, &path);
    try std.testing.expectEqualStrings("10.0.2.2", got.authority);
    try std.testing.expectEqual(@as(u16, 80), got.port);
    try std.testing.expectEqualStrings("/", got.path);
    try std.testing.expect(got.host == .ipv4);
    try std.testing.expectEqualSlices(u8, &.{ 10, 0, 2, 2 }, &got.host.ipv4);
}

test "parse accepts IPv4 with explicit port" {
    var norm: [256]u8 = undefined;
    var host: [128]u8 = undefined;
    var path: [128]u8 = undefined;
    const got = try target.parse("10.0.2.2:8080", &norm, &host, &path);
    try std.testing.expectEqualStrings("10.0.2.2", got.authority);
    try std.testing.expectEqual(@as(u16, 8080), got.port);
}

test "parse strips http scheme and keeps path" {
    var norm: [256]u8 = undefined;
    var host: [128]u8 = undefined;
    var path: [128]u8 = undefined;
    const got = try target.parse("http://example.com/foo", &norm, &host, &path);
    try std.testing.expectEqualStrings("example.com", got.authority);
    try std.testing.expectEqualStrings("/foo", got.path);
    try std.testing.expect(got.host == .hostname);
}

test "parse strips http scheme port and path" {
    var norm: [256]u8 = undefined;
    var host: [128]u8 = undefined;
    var path: [128]u8 = undefined;
    const got = try target.parse("http://example.com:8080/bar", &norm, &host, &path);
    try std.testing.expectEqualStrings("example.com", got.authority);
    try std.testing.expectEqual(@as(u16, 8080), got.port);
    try std.testing.expectEqualStrings("/bar", got.path);
}

test "parse rejects missing host" {
    var norm: [256]u8 = undefined;
    var host: [128]u8 = undefined;
    var path: [128]u8 = undefined;
    try std.testing.expectError(target.ParseError.MissingHost, target.parse("http:///x", &norm, &host, &path));
}

test "parse rejects path overflow" {
    var norm: [256]u8 = undefined;
    var host: [128]u8 = undefined;
    var path: [32]u8 = undefined;
    const long_path = "http://example.com/" ++ "a" ** 64;
    try std.testing.expectError(target.ParseError.PathTooLong, target.parse(long_path, &norm, &host, &path));
}

test "parseHost classifies IPv4 and hostnames" {
    const ipv4 = target.parseHost("10.0.2.2");
    try std.testing.expect(ipv4 == .ipv4);
    try std.testing.expectEqualSlices(u8, &.{ 10, 0, 2, 2 }, &ipv4.ipv4);

    const hostname = target.parseHost("example.com");
    try std.testing.expect(hostname == .hostname);
    try std.testing.expectEqualStrings("example.com", hostname.hostname);
}

test "buildRequest formats HTTP/1.0 GET" {
    var out: [128]u8 = undefined;
    const len = target.buildRequest("example.com", "/bar", &out).?;
    try std.testing.expectEqualStrings(
        "GET /bar HTTP/1.0\r\nHost: example.com\r\n\r\n",
        out[0..len],
    );
}

test "findBodyStart locates header terminator" {
    const data = "HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\nhello";
    try std.testing.expectEqualStrings("hello", target.findBodyStart(data).?);
}

test "resolve flow: IPv4 literal needs no DNS" {
    var norm: [256]u8 = undefined;
    var host: [128]u8 = undefined;
    var path: [128]u8 = undefined;
    const got = try target.parse("10.0.2.2", &norm, &host, &path);
    try std.testing.expect(got.host == .ipv4);
}

test "resolve flow: hostname needs DNS" {
    var norm: [256]u8 = undefined;
    var host: [128]u8 = undefined;
    var path: [128]u8 = undefined;
    const got = try target.parse("http://example.com/", &norm, &host, &path);
    try std.testing.expect(got.host == .hostname);
    try std.testing.expectEqualStrings("example.com", got.host.hostname);
}
