const address = @import("address.zig");
const paging = @import("../arch/x86_64/paging.zig");
const physical = @import("physical.zig");

pub const LoadError = error{
    InvalidElf,
    UnsupportedElf,
    OutOfMemory,
};

pub const LoadedImage = struct {
    entry: u64,
    stack_top: u64,
};

/// Linux-style user stack layout (must match `process.user_stack_top`).
pub const user_stack_top: u64 = 0x00007FFFFFFFE000;
pub const user_stack_pages: usize = 16;

const ElfIdent = struct {
    magic: u32,
    class: u8,
    data: u8,
};

const Elf64Ehdr = extern struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u64,
    e_phoff: u64,
    e_shoff: u64,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

const Elf64Phdr = extern struct {
    p_type: u32,
    p_flags: u32,
    p_offset: u64,
    p_vaddr: u64,
    p_paddr: u64,
    p_filesz: u64,
    p_memsz: u64,
    p_align: u64,
};

const PT_LOAD: u32 = 1;
const ET_EXEC: u16 = 2;
const ET_DYN: u16 = 3;
const EM_X86_64: u16 = 62;
const ELF_MAGIC: u32 = 0x464C457F;
const ELFCLASS64: u8 = 2;
const ELFDATA2LSB: u8 = 1;

const PF_X: u32 = 1;
const PF_W: u32 = 2;

pub fn load(cr3: u64, image: []const u8) LoadError!LoadedImage {
    if (image.len < @sizeOf(Elf64Ehdr)) return LoadError.InvalidElf;

    const hdr: *const Elf64Ehdr = @ptrCast(@alignCast(image.ptr));
    try validateHeader(hdr, image.len);

    const ph_size = @as(usize, hdr.e_phentsize) * hdr.e_phnum;
    if (hdr.e_phoff > image.len or ph_size > image.len - hdr.e_phoff) {
        return LoadError.InvalidElf;
    }

    const phdrs: [*]const Elf64Phdr = @ptrCast(@alignCast(image.ptr + hdr.e_phoff));
    var i: u16 = 0;
    while (i < hdr.e_phnum) : (i += 1) {
        const ph = phdrs[i];
        if (ph.p_type != PT_LOAD) continue;
        try loadSegment(cr3, image, ph);
    }

    const stack_top = try setupUserStack(cr3);
    return .{
        .entry = hdr.e_entry,
        .stack_top = stack_top,
    };
}

fn validateHeader(hdr: *const Elf64Ehdr, image_len: usize) LoadError!void {
    const ident: *const ElfIdent = @ptrCast(&hdr.e_ident);

    if (ident.magic != ELF_MAGIC) return LoadError.InvalidElf;
    if (ident.class != ELFCLASS64 or ident.data != ELFDATA2LSB) return LoadError.UnsupportedElf;
    if (hdr.e_machine != EM_X86_64) return LoadError.UnsupportedElf;
    if (hdr.e_type != ET_EXEC and hdr.e_type != ET_DYN) return LoadError.UnsupportedElf;
    if (hdr.e_phentsize < @sizeOf(Elf64Phdr)) return LoadError.InvalidElf;
    if (hdr.e_phoff >= image_len) return LoadError.InvalidElf;
    _ = hdr.e_shoff;
    _ = hdr.e_shnum;
}

fn segmentFlags(p_flags: u32) u64 {
    var flags: u64 = paging.Flags.user | paging.Flags.present;
    if (p_flags & PF_W != 0) flags |= paging.Flags.writable;
    if (p_flags & PF_X == 0) flags |= paging.Flags.no_exec;
    return flags;
}

fn loadSegment(cr3: u64, image: []const u8, ph: Elf64Phdr) LoadError!void {
    if (ph.p_filesz > image.len or ph.p_offset > image.len - ph.p_filesz) {
        return LoadError.InvalidElf;
    }
    if (ph.p_memsz < ph.p_filesz) return LoadError.InvalidElf;

    const flags = segmentFlags(ph.p_flags);
    const first_page = ph.p_vaddr & ~(paging.page_size - 1);
    const last_page = (ph.p_vaddr + ph.p_memsz + paging.page_size - 1) & ~(paging.page_size - 1);

    var page = first_page;
    while (page < last_page) : (page += paging.page_size) {
        const phys = physical.allocPage() catch return LoadError.OutOfMemory;
        const page_buf = @as([*]u8, @ptrFromInt(address.physToVirt(phys)))[0..paging.page_size];
        @memset(page_buf, 0);

        const page_end = page + paging.page_size;
        const seg_start = @max(page, ph.p_vaddr);
        const seg_end = @min(page_end, ph.p_vaddr + ph.p_memsz);

        if (seg_start < seg_end) {
            const seg_off = seg_start - ph.p_vaddr;
            const page_off = seg_start - page;
            if (seg_off < ph.p_filesz) {
                const file_end = @min(seg_end - ph.p_vaddr, ph.p_filesz);
                const copy_len = file_end - seg_off;
                @memcpy(page_buf[page_off..][0..copy_len], image[ph.p_offset + seg_off ..][0..copy_len]);
            }
        }

        paging.mapUserPageIn(cr3, page, phys, flags) catch return LoadError.OutOfMemory;
    }
}

fn setupUserStack(cr3: u64) LoadError!u64 {
    const stack_end = user_stack_top + paging.page_size;
    const stack_start = stack_end - @as(u64, @intCast(user_stack_pages)) * paging.page_size;

    var page = stack_start;
    while (page < stack_end) : (page += paging.page_size) {
        const phys = physical.allocPage() catch return LoadError.OutOfMemory;
        paging.mapUserPageIn(
            cr3,
            page,
            phys,
            paging.Flags.user | paging.Flags.present | paging.Flags.writable | paging.Flags.no_exec,
        ) catch return LoadError.OutOfMemory;
    }

    return user_stack_top;
}
