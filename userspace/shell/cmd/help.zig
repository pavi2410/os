const io = @import("../io.zig");

pub fn run() void {
    io.writeStr("Built-ins: help, exit, pid, echo, cat, ls, write, rm, mkdir, rmdir\n");
    io.writeStr("  echo [text...]  print a line\n");
    io.writeStr("  ls [-l] [path]  list directory ( -l = type + size )\n");
    io.writeStr("  write [-a] /path text...  create, replace (-a append)\n");
    io.writeStr("  rm /path  delete a file\n");
    io.writeStr("  mkdir /path  create a directory\n");
    io.writeStr("  rmdir /path  remove an empty directory\n");
    io.writeStr("Programs in /BIN: hello, ...\n");
    io.writeStr("Use full paths with cat, e.g. cat /README.TXT\n");
}
