const std = @import("std");
const fd_table = @import("fd_table");

test "init wires stdin stdout stderr as console fds" {
    const table = fd_table.FdTable.init();
    try std.testing.expect(table.fds[0] == .console);
    try std.testing.expect(table.fds[1] == .console);
    try std.testing.expect(table.fds[2] == .console);
    try std.testing.expect(table.fds[3] == .none);
}

test "allocFd skips stdio and returns first free slot" {
    var table = fd_table.FdTable.init();
    const fd3 = table.allocFd().?;
    try std.testing.expectEqual(@as(usize, 3), fd3);
    table.fds[fd3] = .{ .file = 7 };

    const fd4 = table.allocFd().?;
    try std.testing.expectEqual(@as(usize, 4), fd4);
}

test "tagged union stores only the active payload" {
    var table = fd_table.FdTable.init();
    const fd = table.allocFd().?;
    table.fds[fd] = .{ .file = 11 };
    try std.testing.expect(table.fds[fd] == .file);
    try std.testing.expectEqual(@as(u32, 11), table.fds[fd].file);

    table.fds[fd] = .{ .socket = 22 };
    try std.testing.expect(table.fds[fd] == .socket);
    try std.testing.expectEqual(@as(u32, 22), table.fds[fd].socket);
}

test "isOpen reflects none vs active tags" {
    var table = fd_table.FdTable.init();
    try std.testing.expect(table.isOpen(0));
    try std.testing.expect(!table.isOpen(5));

    const fd = table.allocFd().?;
    table.fds[fd] = .{ .file = 1 };
    try std.testing.expect(table.isOpen(fd));

    table.fds[fd] = .none;
    try std.testing.expect(!table.isOpen(fd));
}

test "fd tag coercion matches active variant" {
    const file_fd: fd_table.Fd = .{ .file = 9 };
    try std.testing.expect(@as(fd_table.Fd, file_fd) == .file);
    try std.testing.expectEqualStrings("file", @tagName(file_fd));
}
