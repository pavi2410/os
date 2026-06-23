/// Disable interrupts.
pub inline fn cli() void {
    asm volatile ("cli");
}

/// Enable interrupts.
pub inline fn sti() void {
    asm volatile ("sti");
}

/// Halt until the next interrupt.
pub inline fn hlt() void {
    asm volatile ("hlt");
}

/// Return the address of the next instruction (approximate RIP).
pub inline fn readRip() u64 {
    return asm volatile ("lea (%%rip), %[rip]"
        : [rip] "=r" (-> u64),
    );
}

/// Spin forever, halting the CPU between iterations.
pub fn haltForever() noreturn {
    while (true) hlt();
}

/// Read a model-specific register.
pub inline fn rdmsr(msr: u32) u64 {
    const lo: u32 = undefined;
    const hi: u32 = undefined;
    asm volatile ("rdmsr"
        : [_] "={eax}" (lo),
          [_] "={edx}" (hi),
        : [_] "{ecx}" (msr),
    );
    return (@as(u64, hi) << 32) | lo;
}

/// Write a model-specific register.
pub inline fn wrmsr(msr: u32, value: u64) void {
    const lo: u32 = @truncate(value);
    const hi: u32 = @truncate(value >> 32);
    asm volatile ("wrmsr"
        :
        : [_] "{ecx}" (msr),
          [_] "{eax}" (lo),
          [_] "{edx}" (hi),
    );
}
