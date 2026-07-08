const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;

const arg = @import("argv.zig");
const cwd = @import("cwd.zig");
const environ = @import("environ.zig");
const expand = @import("expand.zig");
const io = @import("io.zig");
const ulib = @import("ulib");
const registry = @import("cmd/registry.zig");

fn writePrompt() void {
    io.writeNewline();
    io.writeStr(cwd.get());
    io.writeStr("> ");
}

export fn main(argc: usize, raw_argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = argc;
    _ = raw_argv;
    environ.init();
    io.writeStr("Simple shell ready. Type 'help'.\n");

    var line: [256]u8 = undefined;
    var expand_bufs: [arg.max_args][expand.max_arg_len]u8 = undefined;
    while (true) {
        writePrompt();

        const n = ulib.io.readStdin(&line);
        if (n <= 0) continue;

        var parsed = arg.parse(&line, @intCast(n)) catch {
            io.writeStr("too many arguments\n");
            continue;
        };
        if (parsed.argc == 0) continue;
        if (!expand.expandArgv(&parsed, &expand_bufs)) {
            io.writeStr("expansion failed\n");
            continue;
        }

        const cmd = parsed.cmd().?;
        _ = registry.dispatch(cmd, &parsed);
    }
}
