pub const Result = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
};

pub fn leaf(leaf_num: u32, subleaf: u32) Result {
    var eax: u32 = leaf_num;
    var ebx: u32 = 0;
    var ecx: u32 = subleaf;
    var edx: u32 = 0;
    asm volatile ("cpuid"
        : [eax] "+{eax}" (eax),
          [ebx] "+{ebx}" (ebx),
          [ecx] "+{ecx}" (ecx),
          [edx] "+{edx}" (edx),
    );
    return .{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}

pub fn maxLeaf() u32 {
    return leaf(0, 0).eax;
}

pub fn vendorString(out: *[12]u8) void {
    var eax: u32 = 0;
    var ebx: u32 = undefined;
    var ecx: u32 = 0;
    var edx: u32 = undefined;
    asm volatile ("cpuid"
        : [eax] "+{eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "+{ecx}" (ecx),
          [edx] "={edx}" (edx),
    );
    writeRegBytes(ebx, out[0..4]);
    writeRegBytes(edx, out[4..8]);
    writeRegBytes(ecx, out[8..12]);
}

pub fn brandString(out: *[48]u8) void {
    @memset(out, 0);

    var eax: u32 = 0x8000_0000;
    var ebx: u32 = undefined;
    var ecx: u32 = 0;
    var edx: u32 = undefined;
    asm volatile ("cpuid"
        : [eax] "+{eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "+{ecx}" (ecx),
          [edx] "={edx}" (edx),
    );
    if (eax < 0x8000_0004) return;

    inline for (.{
        .{ 0x8000_0002, 0 },
        .{ 0x8000_0003, 16 },
        .{ 0x8000_0004, 32 },
    }) |step| {
        eax = step[0];
        ecx = 0;
        asm volatile ("cpuid"
            : [eax] "+{eax}" (eax),
              [ebx] "={ebx}" (ebx),
              [ecx] "+{ecx}" (ecx),
              [edx] "={edx}" (edx),
        );
        writeRegBytes(eax, out[step[1]..][0..4]);
        writeRegBytes(ebx, out[step[1]..][4..8]);
        writeRegBytes(ecx, out[step[1]..][8..12]);
        writeRegBytes(edx, out[step[1]..][12..16]);
    }
}

pub fn familyModelStepping(eax: u32) struct { family: u8, model: u8, stepping: u8 } {
    const stepping: u8 = @truncate(eax & 0xF);
    var model: u8 = @truncate((eax >> 4) & 0xF);
    var family: u8 = @truncate((eax >> 8) & 0xF);
    const ext_model: u8 = @truncate((eax >> 16) & 0xF);
    const ext_family: u8 = @truncate((eax >> 20) & 0xFF);

    if (family == 0xF) family +%= ext_family;
    if (family == 0xF or family == 0x6 or family == 0xE) {
        model +%= ext_model << 4;
    }

    return .{ .family = family, .model = model, .stepping = stepping };
}

fn writeRegBytes(reg: u32, dest: []u8) void {
    dest[0] = @truncate(reg);
    dest[1] = @truncate(reg >> 8);
    dest[2] = @truncate(reg >> 16);
    dest[3] = @truncate(reg >> 24);
}
