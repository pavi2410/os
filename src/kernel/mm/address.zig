/// Virtual ↔ physical address layout for the higher-half kernel.
///
/// The kernel is loaded at a fixed physical address by the UEFI bootloader
/// and linked at the corresponding canonical virtual address in the top 2 GiB
/// (x86_64 kernel code model window):
///
///   VA = HIGHER_HALF_BASE + PA
///
/// Physical layout:
///   0x100000 … _kernel_end   kernel image (.text, .rodata, .data, .bss)
///
/// Virtual layout:
///   0xFFFFFFFF80100000 …     kernel image
///   0xFFFFFFFF80000000 …     direct map of physical address space
pub const KERNEL_PHYS_BASE: u64 = 0x100000;

/// Higher-half base — top 2 GiB of canonical address space (-2 GiB).
pub const HIGHER_HALF_BASE: u64 = 0xFFFFFFFF80000000;

/// Fixed offset between a physical address and its higher-half virtual address.
pub const HIGHER_HALF_OFFSET: u64 = HIGHER_HALF_BASE;

/// Virtual link address of the kernel (HIGHER_HALF_BASE + KERNEL_PHYS_BASE).
pub const KERNEL_VIRT_BASE: u64 = HIGHER_HALF_BASE + KERNEL_PHYS_BASE;

/// Convert a physical address to its higher-half virtual address.
pub inline fn physToVirt(phys: u64) u64 {
    return phys + HIGHER_HALF_OFFSET;
}

/// Convert a higher-half virtual address to its physical address.
pub inline fn virtToPhys(virt: u64) u64 {
    return virt - HIGHER_HALF_OFFSET;
}

/// True when `virt` lies in the canonical higher-half range.
pub inline fn isHigherHalf(virt: u64) bool {
    return virt >= HIGHER_HALF_BASE;
}
