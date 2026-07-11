const address = @import("../mm/address.zig");
const paging = @import("../arch/x86_64/paging.zig");
const process = @import("../proc/process.zig");
const user = @import("user.zig");

pub const Fault = user.Fault;

pub fn copyOut(dest_ptr: u64, data: []const u8) Fault!void {
    const proc = process.currentProcess() orelse return error.Fault;
    try copyOutIn(proc.address_space.cr3, dest_ptr, data);
}

fn copyOutIn(cr3: u64, dest_ptr: u64, data: []const u8) Fault!void {
    if (!user.range(dest_ptr, data.len)) return error.Fault;
    var written: usize = 0;
    while (written < data.len) {
        const addr = dest_ptr + written;
        const page = addr & ~(paging.page_size - 1);
        const off = addr & (paging.page_size - 1);
        const entry = paging.getLeafEntryIn(cr3, page) orelse return error.Fault;
        if (entry.user == 0 or entry.writable == 0) return error.Fault;
        const phys = entry.framePhys();
        const page_virt = address.physToVirt(phys);
        const chunk = @min(data.len - written, paging.page_size - off);
        @memcpy(
            @as([*]u8, @ptrFromInt(page_virt))[off .. off + chunk],
            data[written .. written + chunk],
        );
        written += chunk;
    }
}
