const std = @import("std");
const page_ref = @import("page_ref");

test "retain and release track references" {
    var storage: [8]u32 = .{0} ** 8;
    var table = page_ref.PageRefTable.initFromMaxPfn(&storage, 7);

    const page = 0x3000;
    try table.retain(page);
    try std.testing.expectEqual(@as(u32, 1), table.count(page));

    try table.retain(page);
    try std.testing.expectEqual(@as(u32, 2), table.count(page));

    _ = try table.release(page);
    try std.testing.expectEqual(@as(u32, 1), table.count(page));

    _ = try table.release(page);
    try std.testing.expectEqual(@as(u32, 0), table.count(page));
}

test "release on zero count is rejected" {
    var storage: [4]u32 = .{0} ** 4;
    var table = page_ref.PageRefTable.initFromMaxPfn(&storage, 3);

    try std.testing.expectError(page_ref.RefError.Underflow, table.release(0x1000));
}

test "retain rejects invalid addresses" {
    var storage: [4]u32 = .{0} ** 4;
    var table = page_ref.PageRefTable.initFromMaxPfn(&storage, 3);

    try std.testing.expectError(page_ref.RefError.InvalidAddress, table.retain(0));
    try std.testing.expectError(page_ref.RefError.InvalidAddress, table.retain(0x1001));
    try std.testing.expectError(page_ref.RefError.InvalidAddress, table.retain(0x5000));
}

test "retain overflow is rejected" {
    var storage: [2]u32 = .{0} ** 2;
    var table = page_ref.PageRefTable.initFromMaxPfn(&storage, 1);
    table.counts[1] = std.math.maxInt(u32);

    try std.testing.expectError(page_ref.RefError.Overflow, table.retain(0x1000));
}
