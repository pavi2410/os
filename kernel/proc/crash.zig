const address = @import("../mm/address.zig");
const abi_signal = @import("abi_signal");
const crash_util = @import("crash_util.zig");
const exc_frame = @import("../arch/x86_64/frame.zig");
const paging = @import("../arch/x86_64/paging.zig");
const process = @import("process.zig");
const serial = @import("../arch/x86_64/serial.zig");
const user_loader = @import("../mm/user_loader.zig");

pub const Info = struct {
    vector: u64,
    error_code: u64,
    fault_addr: ?u64 = null,
};

pub const max_backtrace_frames = 16;

pub const exitStatusForVector = crash_util.exitStatusForVector;
pub const signalForVector = crash_util.signalForVector;
pub const exceptionName = crash_util.exceptionName;
pub const signalName = crash_util.signalName;
pub const pageFaultDescription = crash_util.pageFaultDescription;

pub fn isUserTextAddr(cr3: u64, addr: u64) bool {
    if (addr < process.user_brk_base) return false;
    if (addr >= 0x0000800000000000) return false;
    const page = addr & ~@as(u64, paging.page_size - 1);
    const flags = paging.getPageFlagsIn(cr3, page) orelse return false;
    return flags.present != 0 and flags.no_exec == 0;
}

pub fn readUserU64(cr3: u64, virt: u64) ?u64 {
    var bytes: [8]u8 = undefined;
    if (!readUserBytes(cr3, virt, &bytes)) return null;
    return @as(u64, @bitCast(bytes));
}

pub fn readUserBytes(cr3: u64, virt: u64, out: []u8) bool {
    var written: usize = 0;
    while (written < out.len) {
        const addr = virt + written;
        const page = addr & ~@as(u64, paging.page_size - 1);
        const off = addr & (paging.page_size - 1);
        const phys = paging.getPhysIn(cr3, page) orelse return false;
        const page_virt = address.physToVirt(phys);
        const chunk = @min(out.len - written, paging.page_size - off);
        const src = @as([*]const u8, @ptrFromInt(page_virt))[off .. off + chunk];
        @memcpy(out[written .. written + chunk], src);
        written += chunk;
    }
    return true;
}

pub fn walkBacktrace(cr3: u64, rbp: u64, rip: u64, out: []u64) usize {
    var count: usize = 0;
    if (isUserTextAddr(cr3, rip) and count < out.len) {
        out[count] = rip;
        count += 1;
    }

    var fp = rbp;
    const stack_limit = user_loader.user_stack_top + paging.page_size;
    while (count < out.len) {
        if (fp < process.user_brk_base or fp >= stack_limit) break;
        if (fp & 7 != 0) break;

        const ret = readUserU64(cr3, fp + 8) orelse break;
        if (!isUserTextAddr(cr3, ret)) break;
        out[count] = ret;
        count += 1;

        const next_fp = readUserU64(cr3, fp) orelse break;
        if (next_fp <= fp or next_fp >= stack_limit) break;
        fp = next_fp;
    }
    return count;
}

pub fn log(trap: *const exc_frame.Frame, info: Info) void {
    const proc = process.currentProcess();
    const pid = if (proc) |p| p.id else 0;
    const cr3 = if (proc) |p| p.address_space.cr3 else 0;
    const signal = signalForVector(info.vector);

    serial.println("\n--- userspace crash ---", .{});
    serial.println("pid: {d}", .{pid});
    serial.println("exception: {s} (vector {d})", .{ exceptionName(info.vector), info.vector });
    serial.println("signal: {s} ({d})", .{ signalName(signal), signal.number() });

    if (info.vector == 14) {
        const addr = info.fault_addr orelse 0;
        serial.println("fault address: 0x{x}", .{addr});
        serial.println("reason: {s}", .{pageFaultDescription(info.error_code)});
    } else if (info.fault_addr) |addr| {
        serial.println("fault address: 0x{x}", .{addr});
    }

    serial.println("rip: 0x{x}", .{trap.rip});
    serial.println("rbp: 0x{x}", .{trap.rbp});

    if (cr3 != 0) {
        var frames: [max_backtrace_frames]u64 = undefined;
        const n = walkBacktrace(cr3, trap.rbp, trap.rip, &frames);
        if (n > 0) {
            serial.println("backtrace:", .{});
            var i: usize = 0;
            while (i < n) : (i += 1) {
                serial.println("  #{d} 0x{x}", .{ i, frames[i] });
            }
        } else {
            serial.println("backtrace: (unavailable)", .{});
        }
    }

    serial.println("exit status: {d}", .{exitStatusForVector(info.vector)});
    serial.println("-----------------------", .{});
}

pub fn handleUserFault(trap: *exc_frame.Frame, info: Info) noreturn {
    log(trap, info);
    const sig = signalForVector(info.vector);
    process.terminateCurrent(abi_signal.waitStatusForSignal(sig));
}
