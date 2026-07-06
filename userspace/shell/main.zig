const freestanding_std = @import("freestanding_std");
const arg = @import("argv.zig");

pub const std_options_debug_io = freestanding_std.std_options_debug_io;
pub const std_options = freestanding_std.std_options;
const cwd = @import("cwd.zig");
const io = @import("io.zig");
const libc = @import("libc");
const registry = @import("cmd/registry.zig");

fn writePrompt() void {
    io.writeNewline();
    io.writeStr(cwd.get());
    io.writeStr("> ");
}

export fn main(argc: usize, raw_argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    _ = argc;
    _ = raw_argv;
    io.writeStr("Simple shell ready. Type 'help'.\n");

    var line: [256]u8 = undefined;
    while (true) {
        writePrompt();

        const n = libc.io.readStdin(&line);
        if (n <= 0) continue;

        const parsed = arg.parse(&line, @intCast(n)) catch {
            io.writeStr("too many arguments\n");
            continue;
        };
        if (parsed.argc == 0) continue;

        const cmd = parsed.cmd().?;
        registry.dispatch(cmd, &parsed);
    }
}
