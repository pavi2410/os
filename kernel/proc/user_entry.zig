const gdt = @import("../arch/x86_64/gdt.zig");
const paging = @import("../arch/x86_64/paging.zig");

/// IF set; user programs run with interrupts enabled.
const user_rflags: u64 = 0x202;

/// Switch to `cr3`, build an `iretq` frame on the user stack, and enter ring 3.
pub fn jumpToUser(entry: u64, user_stack: u64, cr3: u64) noreturn {
    paging.writeCr3(cr3);

    const user_cs: u64 = gdt.user_code_selector | 3;
    const user_ss: u64 = gdt.user_data_selector | 3;

    var sp = user_stack;
    sp -%= 8;
    @as(*u64, @ptrFromInt(sp)).* = user_ss;
    sp -%= 8;
    @as(*u64, @ptrFromInt(sp)).* = user_stack;
    sp -%= 8;
    @as(*u64, @ptrFromInt(sp)).* = user_rflags;
    sp -%= 8;
    @as(*u64, @ptrFromInt(sp)).* = user_cs;
    sp -%= 8;
    @as(*u64, @ptrFromInt(sp)).* = entry;

    asm volatile ("mov %[sp], %%rsp; iretq"
        :
        : [sp] "r" (sp),
    );

    unreachable;
}
