const ulib = @import("ulib");

pub fn run() noreturn {
    ulib.syscall.rebootPowerOff();
}
