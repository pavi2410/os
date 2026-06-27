const io = @import("../io.zig");

pub fn run() void {
    io.writeStr("Built-ins: help, exit, pid, echo, cat, ls, write\n");
    io.writeStr("  echo [text...]  print a line\n");
    io.writeStr("  ls [-l] [path]  list directory ( -l = type + size )\n");
    io.writeStr("  write [-a] /path text...  create, replace (-a append)\n");
    io.writeStr("Programs in /BIN: hello, ...\n");
    io.writeStr("Use full paths with cat, e.g. cat /README.TXT\n");
}
