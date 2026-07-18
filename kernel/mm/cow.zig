const fork_cow = @import("fork_cow.zig");
const process = @import("../proc/process.zig");

const PfErr = packed struct(u64) {
    present: u1,
    write: u1,
    user: u1,
    reserved: u1,
    fetch: u1,
    _: u59 = 0,
};

/// Make `addr` writable in `proc`, promoting COW if needed (kernel copy-out path).
pub fn ensureWritable(proc: *process.Process, addr: u64) bool {
    return fork_cow.promoteOnWrite(proc.address_space.cr3, addr);
}

/// Handle a user write fault to a present read-only COW page. Returns true if resolved.
pub fn tryHandleUserPageFault(fault_addr: u64, error_code: u64) bool {
    const err: PfErr = @bitCast(error_code);
    if (err.fetch != 0 or err.user == 0 or err.present == 0 or err.write == 0) return false;

    const proc = process.currentProcess() orelse return false;
    return fork_cow.promoteOnWrite(proc.address_space.cr3, fault_addr);
}
