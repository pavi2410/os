const io = @import("../io.zig");

pub fn run() void {
    io.writeStr("Built-ins: help, exit, pid, echo, cat, ls, write, rm, mkdir, rmdir, cd, pwd, date\n");
    io.writeStr("  echo [text...]  print a line\n");
    io.writeStr("  ls [-l] [path]  list directory ( -l = type + size )\n");
    io.writeStr("  write [-a] path text...  create, replace (-a append)\n");
    io.writeStr("  rm path  delete a file\n");
    io.writeStr("  mkdir path  create a directory\n");
    io.writeStr("  rmdir path  remove an empty directory\n");
    io.writeStr("  cd [path]  change working directory (default /)\n");
    io.writeStr("  pwd  print working directory\n");
    io.writeStr("  date  print RTC date and time (UTC)\n");
    io.writeStr("Programs in /BIN: hello, dig, ping, ...\n");
    io.writeStr("  dig [@server] name  DNS A lookup (default server 10.0.2.3)\n");
    io.writeStr("  ping [host]  ICMP echo (default 10.0.2.2)\n");
    io.writeStr("Paths may be absolute (/foo) or relative to the current directory.\n");
}
