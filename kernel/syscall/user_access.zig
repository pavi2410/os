const cow = @import("../mm/cow.zig");
const demand = @import("../mm/demand.zig");
const paging = @import("../arch/x86_64/paging.zig");
const process = @import("../proc/process.zig");
const user = @import("user.zig");

pub fn init() void {
    user.setValidator(validate);
}

fn validate(ptr: u64, len: usize, writable: bool) bool {
    const proc = process.currentProcess() orelse return false;
    if (len == 0) return user.range(ptr, 0);

    const end = ptr + @as(u64, @intCast(len));
    var page = ptr & ~(paging.page_size - 1);
    while (page < end) : (page += paging.page_size) {
        var entry = paging.getLeafEntryIn(proc.address_space.cr3, page) orelse blk: {
            // Demand-paged VMAs are valid but not present until first access.
            if (!demand.ensureMapped(proc, page, writable)) return false;
            break :blk paging.getLeafEntryIn(proc.address_space.cr3, page) orelse return false;
        };
        if (entry.user == 0) return false;
        if (writable and entry.writable == 0) {
            if (entry.cow == 0 or !cow.ensureWritable(proc, page)) return false;
            entry = paging.getLeafEntryIn(proc.address_space.cr3, page) orelse return false;
            if (entry.writable == 0) return false;
        }
    }
    return true;
}
