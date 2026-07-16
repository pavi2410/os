const std = @import("std");
const orphan = @import("orphan");

test "adoptParent rewrites only matching parent" {
    try std.testing.expectEqual(@as(usize, orphan.init_pid), orphan.adoptParent(5, 5));
    try std.testing.expectEqual(@as(usize, 3), orphan.adoptParent(3, 5));
    try std.testing.expectEqual(@as(usize, orphan.init_pid), orphan.adoptParent(orphan.init_pid, orphan.init_pid));
}

test "reparentParentIds updates live and zombie parent lists" {
    var parents = [_]usize{ 2, 5, 5, 7 };
    const changed = orphan.reparentParentIds(&parents, 5);
    try std.testing.expectEqual(@as(usize, 2), changed);
    try std.testing.expectEqual(@as(usize, 2), parents[0]);
    try std.testing.expectEqual(@as(usize, orphan.init_pid), parents[1]);
    try std.testing.expectEqual(@as(usize, orphan.init_pid), parents[2]);
    try std.testing.expectEqual(@as(usize, 7), parents[3]);
}
