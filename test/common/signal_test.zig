const std = @import("std");
const abi_signal = @import("abi_signal");

test "signal mask helpers" {
    const bit = abi_signal.mask(abi_signal.SIGINT);
    try std.testing.expectEqual(@as(u64, 1 << 1), bit);

    const blocked = abi_signal.blockMask(0, bit);
    try std.testing.expectEqual(bit, blocked);

    const unblocked = abi_signal.unblockMask(blocked, bit);
    try std.testing.expectEqual(@as(u64, 0), unblocked);
}

test "wait status encoding" {
    try std.testing.expectEqual(@as(u32, 0x2a00), abi_signal.waitStatusForExit(42));
    try std.testing.expectEqual(@as(u32, 2), abi_signal.waitStatusForSignal(abi_signal.SIGINT));
}

test "valid signal numbers" {
    try std.testing.expect(abi_signal.isValid(abi_signal.SIGINT));
    try std.testing.expect(!abi_signal.isValid(0));
    try std.testing.expect(!abi_signal.isValid(abi_signal.NSIG));
}
