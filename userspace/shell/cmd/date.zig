const io = @import("../io.zig");
const libc = @import("libc");
const time_unix = @import("time_unix");

var timespec_storage: libc.time.Timespec = .{ .tv_sec = 0, .tv_nsec = 0 };

pub fn run() void {
    if (!libc.time.realtime(&timespec_storage)) {
        io.writeStr("date: failed\n");
        return;
    }
    var buf: [32]u8 = undefined;
    const formatted = time_unix.formatUtc(&buf, timespec_storage.tv_sec) orelse {
        io.writeStr("date: failed\n");
        return;
    };
    io.writeStr(formatted);
    io.writeStr(" UTC\n");
}
