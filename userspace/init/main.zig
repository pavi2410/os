const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");

const shell_path: [*:0]const u8 = "/BIN/SHELL";

export fn main() callconv(.{ .x86_64_sysv = .{} }) u8 {
    var shell_pid: ulib.process.ProcessId = -1;

    while (true) {
        if (shell_pid < 0) {
            shell_pid = spawnShell();
            if (shell_pid < 0) {
                ulib.io.writeStr("init: failed to spawn shell\n");
                ulib.process.exit(1);
            }
        }

        var wstatus: u32 = 0;
        const waited = ulib.process.wait(-1, &wstatus, 0);
        if (waited < 0) continue;

        if (waited == shell_pid) {
            shell_pid = -1;
        }
    }
}

fn spawnShell() ulib.process.ProcessId {
    const child = ulib.process.fork();
    if (child < 0) return child;
    if (child == 0) {
        var argv = [_:null]?[*:0]const u8{shell_path};
        var envp = [_:null]?[*:0]const u8{};
        _ = ulib.process.exec(shell_path, &argv, &envp);
        ulib.process.exit(1);
    }
    return child;
}
