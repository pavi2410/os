const argv = @import("../argv.zig");
const io = @import("../io.zig");
const status = @import("status");

const cmd_cat = @import("cat.zig");
const cmd_cd = @import("cd.zig");
const cmd_date = @import("date.zig");
const cmd_echo = @import("echo.zig");
const cmd_exit = @import("exit.zig");
const cmd_poweroff = @import("poweroff.zig");
const cmd_ls = @import("ls.zig");
const cmd_mkdir = @import("mkdir.zig");
const cmd_pid = @import("pid.zig");
const cmd_pwd = @import("pwd.zig");
const cmd_rm = @import("rm.zig");
const cmd_rmdir = @import("rmdir.zig");
const cmd_export = @import("export.zig");
const cmd_false = @import("false.zig");
const cmd_run = @import("run.zig");
const cmd_true = @import("true.zig");
const cmd_unset = @import("unset.zig");
const cmd_write = @import("write.zig");

pub const Handler = union(enum) {
    exit,
    poweroff,
    none: *const fn () u8,
    parsed: *const fn (*const argv.Parsed) u8,
};

pub const Entry = struct {
    name: []const u8,
    handler: Handler,
    summary: ?[]const u8 = null,
};

pub const entries = [_]Entry{
    .{ .name = "help", .handler = .{ .none = printHelp } },
    .{ .name = "exit", .handler = .exit },
    .{ .name = "poweroff", .handler = .poweroff, .summary = "  poweroff  ACPI/QEMU power off" },
    .{ .name = "pid", .handler = .{ .none = cmd_pid.run } },
    .{ .name = "echo", .handler = .{ .parsed = cmd_echo.run }, .summary = "  echo [text...]  print a line" },
    .{ .name = "cat", .handler = .{ .parsed = cmd_cat.run } },
    .{ .name = "ls", .handler = .{ .parsed = cmd_ls.run }, .summary = "  ls [-l] [path]  list directory ( -l = type + size )" },
    .{ .name = "write", .handler = .{ .parsed = cmd_write.run }, .summary = "  write [-a] path text...  create, replace (-a append)" },
    .{ .name = "rm", .handler = .{ .parsed = cmd_rm.run }, .summary = "  rm path  delete a file" },
    .{ .name = "mkdir", .handler = .{ .parsed = cmd_mkdir.run }, .summary = "  mkdir path  create a directory" },
    .{ .name = "rmdir", .handler = .{ .parsed = cmd_rmdir.run }, .summary = "  rmdir path  remove an empty directory" },
    .{ .name = "cd", .handler = .{ .parsed = cmd_cd.run }, .summary = "  cd [path]  change working directory (default /)" },
    .{ .name = "pwd", .handler = .{ .none = cmd_pwd.run }, .summary = "  pwd  print working directory" },
    .{ .name = "date", .handler = .{ .none = cmd_date.run }, .summary = "  date  print RTC date and time (UTC)" },
    .{ .name = "export", .handler = .{ .parsed = cmd_export.run }, .summary = "  export [KEY=value]  set or list environment" },
    .{ .name = "unset", .handler = .{ .parsed = cmd_unset.run }, .summary = "  unset NAME  remove an environment variable" },
    .{ .name = "true", .handler = .{ .none = cmd_true.run }, .summary = "  true  succeed with exit status 0" },
    .{ .name = "false", .handler = .{ .none = cmd_false.run }, .summary = "  false  fail with exit status 1" },
};

pub fn dispatch(cmd: []const u8, parsed: *const argv.Parsed) u8 {
    for (entries) |entry| {
        if (!io.eql(cmd, entry.name)) continue;
        const code = switch (entry.handler) {
            .exit => cmd_exit.run(),
            .poweroff => cmd_poweroff.run(),
            .none => |run| run(),
            .parsed => |run| run(parsed),
        };
        status.set(code);
        return code;
    }

    const code = cmd_run.run(parsed);
    status.set(code);
    return code;
}

pub fn printHelp() u8 {
    io.writeStr("Built-ins:");
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        io.writeStr(if (i == 0) " " else ", ");
        io.writeStr(entries[i].name);
    }
    io.writeNewline();

    for (entries) |entry| {
        if (entry.summary) |summary| {
            io.writeStr(summary);
            io.writeNewline();
        }
    }

    io.writeStr("Programs in /BIN: dig, ping, curl, ip, lscpu, lspci, lsblk, lsmem, ...\n");
    io.writeStr("  dig [@server] name  DNS A lookup (default server 10.0.2.3)\n");
    io.writeStr("  ping [host]  ICMP echo (default 10.0.2.2)\n");
    io.writeStr("  curl <url|host> [port]  HTTP GET (resolves hostnames via DNS)\n");
    io.writeStr("  ip <addr|route|neigh>  show addresses, routes, or neighbors\n");
    io.writeStr("  lscpu  show CPU information\n");
    io.writeStr("  lspci  list PCI devices\n");
    io.writeStr("  lsblk  list block devices\n");
    io.writeStr("  lsmem  list physical memory regions\n");
    io.writeStr("Paths may be absolute (/foo) or relative to the current directory.\n");
    return 0;
}
