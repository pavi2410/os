const argv = @import("argv.zig");
const io = @import("io.zig");
const libc = @import("libc");

const cmd_cat = @import("cmd/cat.zig");
const cmd_echo = @import("cmd/echo.zig");
const cmd_exit = @import("cmd/exit.zig");
const cmd_help = @import("cmd/help.zig");
const cmd_ls = @import("cmd/ls.zig");
const cmd_mkdir = @import("cmd/mkdir.zig");
const cmd_pid = @import("cmd/pid.zig");
const cmd_rm = @import("cmd/rm.zig");
const cmd_run = @import("cmd/run.zig");
const cmd_write = @import("cmd/write.zig");

const prompt = "os> ";

export fn main() callconv(.{ .x86_64_sysv = .{} }) void {
    io.writeStr("Simple shell ready. Type 'help'.\n");

    var line: [256]u8 = undefined;
    while (true) {
        io.writeStr(prompt);

        const n = libc.syscall.read(0, &line, line.len);
        if (n <= 0) continue;

        const parsed = argv.parse(&line, @intCast(n)) catch {
            io.writeStr("too many arguments\n");
            continue;
        };
        if (parsed.argc == 0) continue;

        const cmd = parsed.cmd().?;

        if (io.eql(cmd, "exit")) {
            cmd_exit.run();
        } else if (io.eql(cmd, "help")) {
            cmd_help.run();
        } else if (io.eql(cmd, "pid")) {
            cmd_pid.run();
        } else if (io.eql(cmd, "echo")) {
            cmd_echo.run(&parsed);
        } else if (io.eql(cmd, "ls")) {
            cmd_ls.run(&parsed);
        } else if (io.eql(cmd, "write")) {
            cmd_write.run(&parsed);
        } else if (io.eql(cmd, "cat")) {
            cmd_cat.run(&parsed);
        } else if (io.eql(cmd, "rm")) {
            cmd_rm.run(&parsed);
        } else if (io.eql(cmd, "mkdir")) {
            cmd_mkdir.run(&parsed);
        } else if (cmd.len > 0 and cmd[0] == '/') {
            io.writeStr("unknown command\n");
        } else {
            cmd_run.run(cmd);
        }
    }
}
