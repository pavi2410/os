const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const arg = @import("argv.zig");
const cwd = @import("cwd.zig");
const environ = @import("environ.zig");
const expand = @import("expand.zig");
const io = @import("io.zig");
const line_mod = @import("line.zig");
const ulib = @import("ulib");

fn writePrompt() void {
    io.writeNewline();
    io.writeStr(cwd.get());
    io.writeStr("> ");
}

export fn main(argc: usize, raw_argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = argc;
    _ = raw_argv;
    environ.init();
    _ = ulib.signal.ignore(ulib.signal.SIGINT);
    io.writeStr("Simple shell ready. Type 'help'.\n");

    var line: [256]u8 = undefined;
    var expand_bufs: [arg.max_args][expand.max_arg_len]u8 = undefined;
    while (true) {
        writePrompt();

        const n = ulib.io.readStdin(&line);
        if (n <= 0) continue;

        const effective_len = line_mod.stripComment(&line, @intCast(n));
        if (effective_len == 0) continue;

        line_mod.executeLine(line[0..effective_len], &expand_bufs);
    }
}
