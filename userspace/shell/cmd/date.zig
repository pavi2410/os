const io = @import("../io.zig");
const ulib = @import("ulib");
const time_unix = @import("time_unix");

var timespec_storage: ulib.time.Timespec = .{ .tv_sec = 0, .tv_nsec = 0 };

pub fn run() u8 {
    if (!ulib.time.realtime(&timespec_storage)) {
        io.writeStr("date: failed\n");
        return 1;
    }
    var buf: [32]u8 = undefined;
    const formatted = time_unix.formatUtc(&buf, timespec_storage.tv_sec) orelse {
        io.writeStr("date: failed\n");
        return 1;
    };
    io.writeStr(formatted);
    io.writeStr(" UTC\n");
    return 0;
}
