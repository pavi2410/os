const path = @import("ulib").path;
const ulib = @import("ulib");

const Cwd = path.Path(128);
var storage: Cwd = Cwd.root();

pub fn get() []const u8 {
    const n = ulib.fs.getcwd(storage.bufPtr(), storage.capacity());
    if (n < 0) return "/";
    storage.setLen(@intCast(n)) catch return "/";
    return storage.slice();
}

pub fn set(path_str: []const u8) bool {
    storage.set(path_str) catch return false;
    return ulib.fs.chdir(storage.cPtr()) == 0;
}
