/// Minimal TAP 13 writer for freestanding kernel and userspace test harnesses.
pub fn Harness(comptime writeFn: *const fn ([]const u8) void) type {
    return struct {
        var next: u32 = 1;
        var failed: u32 = 0;
        var planned: ?u32 = null;
        var ran: u32 = 0;

        pub fn version() void {
            writeFn("TAP version 13\n");
        }

        pub fn plan(count: u32) void {
            planned = count;
            var buf: [32]u8 = undefined;
            const line = formatPlan(count, &buf);
            writeFn(line);
        }

        pub fn ok(name: []const u8) void {
            emitResult(true, name, null);
        }

        pub fn notOk(name: []const u8, diag: ?[]const u8) void {
            failed += 1;
            emitResult(false, name, diag);
        }

        pub fn check(name: []const u8, passed: bool) void {
            if (passed) ok(name) else notOk(name, "failed");
        }

        pub fn checkEq(comptime T: type, name: []const u8, expected: T, actual: T) void {
            if (expected == actual) {
                ok(name);
            } else {
                notOk(name, "not equal");
            }
        }

        pub fn finish() u8 {
            if (planned) |count| {
                if (ran != count) notOk("plan mismatch", "planned count not reached");
            }
            return if (failed > 0) 1 else 0;
        }

        fn emitResult(pass: bool, name: []const u8, diag: ?[]const u8) void {
            var buf: [160]u8 = undefined;
            const prefix = if (pass) "ok " else "not ok ";
            var len: usize = 0;
            len += copySlice(buf[len..], prefix);
            len += writeU32(buf[len..], next);
            next += 1;
            ran += 1;
            len += copySlice(buf[len..], " - ");
            len += copySlice(buf[len..], name);
            len += copySlice(buf[len..], "\n");
            writeFn(buf[0..len]);
            if (!pass) {
                if (diag) |msg| {
                    var diag_buf: [192]u8 = undefined;
                    const diag_len = formatDiag(&diag_buf, msg);
                    writeFn(diag_buf[0..diag_len]);
                }
            }
        }

        fn formatPlan(count: u32, out: []u8) []const u8 {
            var len: usize = 0;
            len += writeU32(out[len..], 1);
            len += copySlice(out[len..], "..");
            len += writeU32(out[len..], count);
            len += copySlice(out[len..], "\n");
            return out[0..len];
        }

        fn formatDiag(out: []u8, msg: []const u8) usize {
            var len: usize = 0;
            len += copySlice(out[len..], "  ---\n");
            len += copySlice(out[len..], "  ");
            len += copySlice(out[len..], msg);
            len += copySlice(out[len..], "\n");
            len += copySlice(out[len..], "  ...\n");
            return len;
        }

        fn copySlice(out: []u8, src: []const u8) usize {
            if (src.len > out.len) return 0;
            @memcpy(out[0..src.len], src);
            return src.len;
        }

        fn writeU32(out: []u8, value: u32) usize {
            var tmp: [10]u8 = undefined;
            var n = value;
            var len: usize = 0;
            if (n == 0) {
                tmp[0] = '0';
                len = 1;
            } else {
                while (n > 0) : (len += 1) {
                    tmp[len] = @truncate('0' + (n % 10));
                    n /= 10;
                }
            }
            if (len > out.len) return 0;
            var i: usize = 0;
            while (i < len) : (i += 1) {
                out[i] = tmp[len - 1 - i];
            }
            return len;
        }
    };
}
