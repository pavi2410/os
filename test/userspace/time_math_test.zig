const std = @import("std");
const time_math = @import("time_math");

const Timespec = struct {
    tv_sec: i64,
    tv_nsec: i64,
};

test "timespecUs converts positive timestamps" {
    try std.testing.expectEqual(@as(u64, 1_002_003), time_math.timespecUs(Timespec{
        .tv_sec = 1,
        .tv_nsec = 2_003_000,
    }));
}

test "timespecUs rejects negative fields" {
    try std.testing.expectEqual(@as(u64, 0), time_math.timespecUs(Timespec{
        .tv_sec = -1,
        .tv_nsec = 0,
    }));
    try std.testing.expectEqual(@as(u64, 0), time_math.timespecUs(Timespec{
        .tv_sec = 1,
        .tv_nsec = -1,
    }));
}

test "elapsedUs saturates clock rollback" {
    try std.testing.expectEqual(@as(u64, 5), time_math.elapsedUs(10, 15));
    try std.testing.expectEqual(@as(u64, 0), time_math.elapsedUs(15, 10));
}
