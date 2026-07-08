const std = @import("std");

/// Fixed-capacity, length-tracked UTF-8 byte string (NUL-terminated in `buf`).
pub fn String(comptime cap: usize) type {
    comptime {
        if (cap < 2) @compileError("String cap must be at least 2");
    }

    return struct {
        len: usize,
        buf: [cap]u8,

        const Self = @This();

        pub const Error = error{
            TooLong,
            Empty,
        };

        pub fn empty() Self {
            return .{ .len = 0, .buf = [_]u8{0} ** cap };
        }

        /// Initialize from a compile-time string literal.
        pub fn from(comptime literal: []const u8) Self {
            comptime {
                if (literal.len == 0) @compileError("string literal must not be empty");
                if (literal.len >= cap) @compileError("string literal exceeds capacity");
            }
            var s = Self.empty();
            @memcpy(s.buf[0..literal.len], literal);
            s.buf[literal.len] = 0;
            s.len = literal.len;
            return s;
        }

        pub fn slice(self: *const Self) []const u8 {
            return self.buf[0..self.len];
        }

        pub fn capacity(_: *const Self) usize {
            return cap;
        }

        pub fn bufPtr(self: *Self) [*]u8 {
            return self.buf[0..].ptr;
        }

        pub fn cPtr(self: *Self) [*:0]u8 {
            return @ptrCast(self.buf[0..].ptr);
        }

        pub fn set(self: *Self, data: []const u8) Error!void {
            if (data.len == 0) return Error.Empty;
            if (data.len >= cap) return Error.TooLong;
            @memcpy(self.buf[0..data.len], data);
            self.buf[data.len] = 0;
            self.len = data.len;
        }

        /// Set length after an external write (e.g. `getcwd`); `n` excludes the NUL.
        pub fn setLen(self: *Self, n: usize) Error!void {
            if (n == 0) return Error.Empty;
            if (n >= cap) return Error.TooLong;
            self.len = n;
            self.buf[n] = 0;
        }

        pub fn eql(self: *const Self, other: []const u8) bool {
            return std.mem.eql(u8, self.slice(), other);
        }
    };
}
