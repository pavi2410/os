const bytes = @import("common_bytes");
const dns_codec = @import("dns_codec");
const tap = @import("utest_tap");

pub fn runAll() u8 {
    tap.Harness.version();
    tap.Harness.plan(5);
    testBytesBe();
    testBytesLe();
    testDnsBuildQuery();
    testDnsEncodeNameRejects();
    testDnsParseFirstA();
    return tap.Harness.finish();
}

fn testBytesBe() void {
    var buf: [8]u8 = .{0} ** 8;
    bytes.writeU16Be(&buf, 1, 0x1234);
    bytes.writeU32Be(&buf, 3, 0x89AB_CDEF);
    const ok = bytes.readU16Be(&buf, 1) == 0x1234 and
        bytes.readU32Be(&buf, 3) == 0x89AB_CDEF and
        buf[1] == 0x12 and
        buf[6] == 0xEF;
    tap.Harness.check("bytes big endian helpers", ok);
}

fn testBytesLe() void {
    var buf: [8]u8 = .{0} ** 8;
    bytes.writeU16Le(&buf, 1, 0x1234);
    bytes.writeU32Le(&buf, 3, 0x89AB_CDEF);
    const ok = bytes.readU16Le(&buf, 1) == 0x1234 and
        bytes.readU32Le(&buf, 3) == 0x89AB_CDEF and
        bytes.readU64Le(&.{ 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11 }, 0) == 0x1122_3344_5566_7788;
    tap.Harness.check("bytes little endian helpers", ok);
}

fn testDnsBuildQuery() void {
    var query: [256]u8 = undefined;
    const len = dns_codec.buildQuery("example.com", &query) catch {
        tap.Harness.notOk("dns buildQuery example.com", "buildQuery failed");
        return;
    };

    const ok = query[2] == 0x01 and
        query[5] == 0x01 and
        query[12] == 7 and
        query[13] == 'e' and query[14] == 'x' and query[15] == 'a' and
        query[20] == 3 and
        query[21] == 'c' and query[22] == 'o' and query[23] == 'm' and
        query[24] == 0 and
        query[len - 4] == 0x00 and
        query[len - 3] == 0x01;
    tap.Harness.check("dns buildQuery example.com", ok);
}

fn testDnsEncodeNameRejects() void {
    var out: [64]u8 = undefined;
    const empty = dns_codec.encodeName("", &out);
    const leading_dot = dns_codec.encodeName(".example.com", &out);
    tap.Harness.check("dns encodeName rejects bad names", empty == error.BadName and leading_dot == error.BadName);
}

fn testDnsParseFirstA() void {
    const reply = [_]u8{
        0x12, 0x34, 0x81, 0x80, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
        7,    'e',  'x',  'a',  'm',  'p',  'l',  'e',  3,    'c',  'o',  'm',  0,
        0x00, 0x01, 0x00, 0x01,
        0xC0, 0x0C, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3C, 0x00, 0x04,
        104,  20,   23,   154,
    };

    var ip: [4]u8 = undefined;
    const ok = dns_codec.parseFirstA(&reply, &ip) and ip[0] == 104 and ip[3] == 154;
    tap.Harness.check("dns parseFirstA", ok);
}
