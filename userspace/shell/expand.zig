const argv = @import("argv.zig");
const environ = @import("environ.zig");
const status = @import("status");

pub const max_arg_len = 256;
pub const LookupFn = *const fn (name: []const u8) ?[]const u8;

pub fn expandArgv(parsed: *argv.Parsed, storage: *[argv.max_args][max_arg_len]u8) bool {
    return expandArgvWith(parsed, storage, environ.getValue);
}

pub fn expandArgvWith(
    parsed: *argv.Parsed,
    storage: *[argv.max_args][max_arg_len]u8,
    lookup: LookupFn,
) bool {
    var i: usize = 0;
    while (i < parsed.argc) : (i += 1) {
        const expanded = expandWith(parsed.args[i], &storage[i], lookup) orelse return false;
        storage[i][expanded.len] = 0;
        parsed.args[i] = expanded;
    }
    return true;
}

pub fn expand(input: []const u8, out: []u8) ?[]const u8 {
    return expandWith(input, out, environ.getValue);
}

pub fn expandWith(input: []const u8, out: []u8, lookup: LookupFn) ?[]const u8 {
    var out_len: usize = 0;
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '$' and i + 1 < input.len and input[i + 1] == '?') {
            const digits = status.formatTo(out[out_len..]) orelse return null;
            out_len += digits.len;
            i += 2;
            continue;
        }

        if (input[i] == '$' and i + 1 < input.len and isNameStart(input[i + 1])) {
            const name_start = i + 1;
            var name_end = name_start;
            while (name_end < input.len and isNameChar(input[name_end])) : (name_end += 1) {}

            if (lookup(input[name_start..name_end])) |value| {
                if (out_len + value.len > out.len) return null;
                @memcpy(out[out_len .. out_len + value.len], value);
                out_len += value.len;
            }

            i = name_end;
            continue;
        }

        if (out_len >= out.len) return null;
        out[out_len] = input[i];
        out_len += 1;
        i += 1;
    }

    return out[0..out_len];
}

fn isNameStart(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        ch == '_';
}

fn isNameChar(ch: u8) bool {
    return isNameStart(ch) or (ch >= '0' and ch <= '9');
}
