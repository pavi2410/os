/// Architecture-neutral syscall entry facade.
const arch = @import("../arch/x86_64/syscall_entry.zig");
pub const init = arch.init;
