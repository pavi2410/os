const crash_util = @import("crash_util");
const std = @import("std");

test "signal mapping matches Linux conventions" {
    try std.testing.expectEqual(@as(u32, 11), crash_util.signalForVector(14));
    try std.testing.expectEqual(@as(u32, 11), crash_util.signalForVector(13));
    try std.testing.expectEqual(@as(u32, 4), crash_util.signalForVector(6));
    try std.testing.expectEqual(@as(u32, 139), crash_util.exitStatusForVector(14));
}

test "page fault descriptions" {
    try std.testing.expectEqualStrings("read from unmapped page", crash_util.pageFaultDescription(0x4));
    try std.testing.expectEqualStrings("write to unmapped page", crash_util.pageFaultDescription(0x6));
    try std.testing.expectEqualStrings("write to read-only page", crash_util.pageFaultDescription(0x3));
    try std.testing.expectEqualStrings(
        "instruction fetch to non-executable page",
        crash_util.pageFaultDescription(0x14),
    );
    try std.testing.expectEqualStrings("access violation", crash_util.pageFaultDescription(0x1));
}

test "exception names" {
    try std.testing.expectEqualStrings("#PF page fault", crash_util.exceptionName(14));
    try std.testing.expectEqualStrings("#UD invalid opcode", crash_util.exceptionName(6));
}
