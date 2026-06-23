/// Boot information structure passed from bootloader to kernel
/// This structure is passed via RDI register on kernel entry
pub const BootInfo = struct {
    /// Memory map from UEFI
    memory_map: MemoryMap,

    /// Physical address range of the loaded kernel image
    kernel_phys_start: u64,
    kernel_phys_end: u64,

    /// Reserved for future use (framebuffer, ACPI tables, etc.)
    reserved: [40]u8 = [_]u8{0} ** 40,
};

pub const MemoryMap = struct {
    /// Pointer to the memory map buffer
    entries: [*]align(8) u8,
    /// Total size of the memory map in bytes
    size: usize,
    /// Size of each descriptor
    descriptor_size: usize,
    /// Descriptor version
    descriptor_version: u32,
    /// Number of descriptors
    count: usize,
};
