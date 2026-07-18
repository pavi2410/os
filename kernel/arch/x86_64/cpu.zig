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

/// Briefly enable interrupts while yielding inside a polling loop.
pub inline fn relaxInterruptible() void {
    asm volatile ("sti; pause; cli" ::: .{ .memory = true });
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
    var lo: u32 = undefined;
    var hi: u32 = undefined;
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

/// Output a byte to an I/O port.
pub inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
    );
}

/// Output a 16-bit value to an I/O port.
pub inline fn outw(port: u16, value: u16) void {
    asm volatile ("outw %[value], %[port]"
        :
        : [value] "{ax}" (value),
          [port] "{dx}" (port),
    );
}

/// Input a byte from an I/O port.
pub inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

/// Output a 32-bit value to an I/O port.
pub inline fn outl(port: u16, value: u32) void {
    asm volatile ("outl %[value], %[port]" : : [value] "{eax}" (value), [port] "{dx}" (port));
}

/// Input a 32-bit value from an I/O port.
pub inline fn inl(port: u16) u32 {
    return asm volatile ("inl %[port], %[result]" : [result] "={eax}" (-> u32), : [port] "{dx}" (port));
}

/// Prevent the compiler from reordering memory accesses across a device handoff.
pub inline fn compilerMemoryBarrier() void {
    asm volatile ("" ::: .{ .memory = true });
}

/// Replace the current stack pointer during early architecture bootstrap.
pub inline fn switchStack(stack_top: usize) void {
    asm volatile ("mov %[stack], %%rsp" : : [stack] "r" (stack_top));
}
