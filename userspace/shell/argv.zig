//! Split a shell line into null-terminated tokens (in-place) and query flags/args.

pub const max_args = 16;

pub const ParseError = error{
    TooManyArgs,
};

pub const Parsed = struct {
    argc: usize = 0,
    args: [max_args][]const u8 = undefined,

    pub fn cmd(self: *const Parsed) ?[]const u8 {
        if (self.argc == 0) return null;
        return self.args[0];
    }

    pub fn hasFlag(self: *const Parsed, c: u8) bool {
        var i: usize = 1;
        while (i < self.argc) : (i += 1) {
            const arg = self.args[i];
            if (!isFlag(arg)) continue;
            for (arg[1..]) |ch| {
                if (ch == c) return true;
            }
        }
        return false;
    }

    /// Return the positional argument at `index` (0 = first non-flag after the command).
    pub fn positionalAt(self: *const Parsed, index: usize) ?[]const u8 {
        var i: usize = 1;
        var n: usize = 0;
        while (i < self.argc) : (i += 1) {
            const arg = self.args[i];
            if (isFlag(arg)) continue;
            if (n == index) return arg;
            n += 1;
        }
        return null;
    }

    /// Join positional arguments starting at `start` with spaces into `out`.
    pub fn joinPositionalsFrom(self: *const Parsed, out: []u8, start: usize) ParseError![]const u8 {
        var len: usize = 0;
        var i: usize = 1;
        var n: usize = 0;
        var first = true;

        while (i < self.argc) : (i += 1) {
            const arg = self.args[i];
            if (isFlag(arg)) continue;
            if (n < start) {
                n += 1;
                continue;
            }
            n += 1;

            if (!first) {
                if (len >= out.len) return ParseError.TooManyArgs;
                out[len] = ' ';
                len += 1;
            }
            first = false;

            if (len + arg.len > out.len) return ParseError.TooManyArgs;
            @memcpy(out[len .. len + arg.len], arg);
            len += arg.len;
        }

        return out[0..len];
    }
};

pub fn isFlag(arg: []const u8) bool {
    return arg.len >= 2 and arg[0] == '-';
}

/// Tokenize `line[0..len]` in place (spaces become NUL) into `Parsed.argv`.
pub fn parse(line: []u8, len: usize) ParseError!Parsed {
    var end = len;
    while (end > 0 and (line[end - 1] == '\n' or line[end - 1] == '\r')) end -= 1;

    var parsed: Parsed = .{};
    var i: usize = 0;

    while (i < end) {
        while (i < end and line[i] == ' ') i += 1;
        if (i >= end) break;

        if (parsed.argc >= max_args) return ParseError.TooManyArgs;

        const start = i;
        while (i < end and line[i] != ' ') i += 1;
        line[i] = 0;
        parsed.args[parsed.argc] = line[start..i];
        parsed.argc += 1;
        i += 1;
    }

    return parsed;
}
