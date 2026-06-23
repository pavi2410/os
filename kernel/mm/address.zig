/// Virtual ↔ physical address helpers for the higher-half kernel.
///
/// The kernel is linked in the top 2 GiB of canonical address space
/// (x86_64 kernel code model window). Limine loads the executable at its
/// linked virtual address and provides a Higher Half Direct Map (HHDM) for
/// accessing physical memory:
///
///   phys_to_virt(PA) = PA + hhdm_offset
///   virt_to_phys(VA) = VA - hhdm_offset
pub const HIGHER_HALF_BASE: u64 = 0xFFFFFFFF80000000;

/// Virtual link address of the kernel image.
pub const KERNEL_VIRT_BASE: u64 = HIGHER_HALF_BASE;

var hhdm_offset: u64 = 0;

pub fn setHhdmOffset(offset: u64) void {
    hhdm_offset = offset;
}

pub fn hhdmOffset() u64 {
    return hhdm_offset;
}

/// Convert a physical address to its HHDM virtual address.
pub inline fn physToVirt(phys: u64) u64 {
    return phys + hhdm_offset;
}

/// Convert an HHDM virtual address to its physical address.
pub inline fn virtToPhys(virt: u64) u64 {
    return virt - hhdm_offset;
}

/// True when `virt` lies in the canonical higher-half range.
pub inline fn isHigherHalf(virt: u64) bool {
    return virt >= HIGHER_HALF_BASE;
}
