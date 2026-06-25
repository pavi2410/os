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

pub const kernel_code_selector: u16 = 0x08;
pub const kernel_data_selector: u16 = 0x10;

var gdt: [3]GdtEntry = .{
    .{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0, .limit_high_flags = 0, .base_high = 0 },
    .{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0x9A, .limit_high_flags = 0xA0, .base_high = 0 },
    .{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0x92, .limit_high_flags = 0xC0, .base_high = 0 },
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
    );
}

extern fn gdt_load(ptr: *const GdtPointer) callconv(.{ .x86_64_sysv = .{} }) void;

pub fn init() void {
    // Static initializer above defines null, 64-bit code, and data segments.
}

pub fn load() void {
    const ptr = GdtPointer{
        .limit = @sizeOf(@TypeOf(gdt)) - 1,
        .base = @intFromPtr(&gdt),
    };
    gdt_load(&ptr);
}
