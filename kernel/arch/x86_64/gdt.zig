const GdtEntry = packed struct(u64) {
    limit_low: u16,
    base_low: u16,
    base_mid: u8,
    access: u8,
    limit_high_flags: u8,
    base_high: u8,
};

const GdtPointer = packed struct {
    limit: u16,
    base: u64,
};

/// Minimal 64-bit TSS; only `rsp0` is used for ring-0 stack on ring-3 exceptions.
pub const Tss = extern struct {
    reserved0: u32 = 0,
    rsp0: u64 = 0,
    rsp1: u64 = 0,
    rsp2: u64 = 0,
    reserved1: u64 = 0,
    reserved2: u64 = 0,
    reserved3: u64 = 0,
    reserved4: u32 = 0,
    reserved5: u32 = 0,
    ist1: u64 = 0,
    ist2: u64 = 0,
    ist3: u64 = 0,
    ist4: u64 = 0,
    ist5: u64 = 0,
    ist6: u64 = 0,
    ist7: u64 = 0,
    reserved6: u64 = 0,
    reserved7: u32 = 0,
    iopb_offset: u16 = 0,
    reserved8: u16 = 0,
};

pub const kernel_code_selector: u16 = 0x08;
pub const kernel_data_selector: u16 = 0x10;
pub const user_code_selector: u16 = 0x18;
pub const user_data_selector: u16 = 0x20;
pub const tss_selector: u16 = 0x28;

var tss: Tss = .{};
var gdt: [7]GdtEntry = .{
    .{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0, .limit_high_flags = 0, .base_high = 0 },
    .{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0x9A, .limit_high_flags = 0xA0, .base_high = 0 },
    .{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0x92, .limit_high_flags = 0xC0, .base_high = 0 },
    .{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0xFA, .limit_high_flags = 0xA0, .base_high = 0 },
    .{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0xF2, .limit_high_flags = 0xC0, .base_high = 0 },
    .{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0, .limit_high_flags = 0, .base_high = 0 },
    .{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0, .limit_high_flags = 0, .base_high = 0 },
};

comptime {
    asm (
        \\.global gdt_load
        \\.type gdt_load, @function
        \\gdt_load:
        \\  lgdt (%rdi)
        \\  mov $0x10, %ax
        \\  mov %ax, %ds
        \\  mov %ax, %es
        \\  mov %ax, %fs
        \\  mov %ax, %gs
        \\  mov %ax, %ss
        \\  push $0x08
        \\  lea 1f(%rip), %rax
        \\  push %rax
        \\  lretq
        \\1:
        \\  retq
        \\
        \\.global tss_load
        \\.type tss_load, @function
        \\tss_load:
        \\  ltr %di
        \\  retq
    );
}

extern fn gdt_load(ptr: *const GdtPointer) callconv(.{ .x86_64_sysv = .{} }) void;
extern fn tss_load(selector: u16) callconv(.{ .x86_64_sysv = .{} }) void;

fn installTssDescriptor() void {
    const base = @intFromPtr(&tss);
    const limit: u32 = @sizeOf(Tss) - 1;

    gdt[5] = .{
        .limit_low = @truncate(limit),
        .base_low = @truncate(base),
        .base_mid = @truncate(base >> 16),
        .access = 0x89,
        .limit_high_flags = @truncate((limit >> 16) & 0xF),
        .base_high = @truncate(base >> 24),
    };
    gdt[6] = .{
        .limit_low = @truncate(base >> 32),
        .base_low = @truncate(base >> 48),
        .base_mid = 0,
        .access = 0,
        .limit_high_flags = 0,
        .base_high = 0,
    };
}

pub fn setKernelStack(stack_top: u64) void {
    tss.rsp0 = stack_top;
}

pub fn init() void {
    installTssDescriptor();
}

pub fn load() void {
    const ptr = GdtPointer{
        .limit = @sizeOf(@TypeOf(gdt)) - 1,
        .base = @intFromPtr(&gdt),
    };
    gdt_load(&ptr);
    tss_load(tss_selector);
}
