pub const flags = struct {
    pub const next: u16 = 1;
    pub const write: u16 = 2;
};

pub const Segment = struct {
    phys: u64,
    len: u32,
    writable: bool = false,
};

pub fn descriptorFlags(has_next: bool, writable: bool) u16 {
    var out: u16 = 0;
    if (has_next) out |= flags.next;
    if (writable) out |= flags.write;
    return out;
}
