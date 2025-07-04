const std = @import("std");
const uefi = std.os.uefi;

pub fn main() void {
    const con_out = uefi.system_table.con_out.?;
    _ = con_out.outputString(&[_:0]u16{ 'H', 'e', 'l', 'l', '\n' });
}
