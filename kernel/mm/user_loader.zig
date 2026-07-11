const address = @import("address.zig");
const page_ref = @import("page_ref.zig");
const paging = @import("../arch/x86_64/paging.zig");
const physical = @import("physical.zig");
const std = @import("std");
const elf = std.elf;

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
pub const user_top: u64 = 0x0000_8000_0000_0000;

pub const max_argv = 16;
pub const max_envp = 16;
pub const max_string_len = 256;

pub fn load(cr3: u64, image: []const u8, argv: []const []const u8, envp: []const []const u8) LoadError!LoadedImage {
    if (image.len < @sizeOf(elf.Elf64_Ehdr)) return LoadError.InvalidElf;

    const hdr: *const elf.Elf64_Ehdr = @ptrCast(@alignCast(image.ptr));
    try validateHeader(hdr, image.len);
    if (hdr.e_entry >= user_top) return LoadError.InvalidElf;

    const ph_size = @as(usize, hdr.e_phentsize) * hdr.e_phnum;
    if (hdr.e_phoff > image.len or ph_size > image.len - hdr.e_phoff) {
        return LoadError.InvalidElf;
    }

    const phdrs: [*]const elf.Elf64_Phdr = @ptrCast(@alignCast(image.ptr + hdr.e_phoff));
    var i: u16 = 0;
    while (i < hdr.e_phnum) : (i += 1) {
        const ph = phdrs[i];
        if (ph.p_type != elf.PT_LOAD) continue;
        try loadSegment(cr3, image, ph);
    }

    const stack_top = try setupUserStack(cr3);
    const sp = try pushInitialStack(cr3, stack_top, argv, envp);
    return .{
        .entry = hdr.e_entry,
        .stack_top = sp,
    };
}

fn validateHeader(hdr: *const elf.Elf64_Ehdr, image_len: usize) LoadError!void {
    if (!std.mem.eql(u8, hdr.e_ident[0..4], elf.MAGIC)) return LoadError.InvalidElf;
    if (hdr.e_ident[elf.EI.CLASS] != @intFromEnum(elf.CLASS.@"64")) return LoadError.UnsupportedElf;
    if (hdr.e_ident[elf.EI.DATA] != @intFromEnum(elf.DATA.@"2LSB")) return LoadError.UnsupportedElf;
    if (hdr.e_machine != .X86_64) return LoadError.UnsupportedElf;
    if (hdr.e_type != .EXEC) return LoadError.UnsupportedElf;
    if (hdr.e_phentsize != @sizeOf(elf.Elf64_Phdr)) return LoadError.InvalidElf;
    if (hdr.e_phoff >= image_len) return LoadError.InvalidElf;
    _ = hdr.e_shoff;
    _ = hdr.e_shnum;
}

fn segmentFlags(p_flags: u32) paging.Pte {
    var pte = paging.Pte{ .present = 1, .user = 1 };
    if (p_flags & elf.PF_W != 0) pte.writable = 1;
    if (p_flags & elf.PF_X == 0) pte.no_exec = 1;
    return pte;
}

fn mergeSegmentPageFlags(existing: paging.Pte, incoming: paging.Pte) paging.Pte {
    return paging.Pte.mergePermissions(existing, incoming);
}

fn loadSegment(cr3: u64, image: []const u8, ph: elf.Elf64_Phdr) LoadError!void {
    if (ph.p_filesz > image.len or ph.p_offset > image.len - ph.p_filesz) {
        return LoadError.InvalidElf;
    }
    if (ph.p_memsz < ph.p_filesz) return LoadError.InvalidElf;
    if (ph.p_vaddr >= user_top or ph.p_memsz > user_top - ph.p_vaddr) {
        return LoadError.InvalidElf;
    }

    const flags = segmentFlags(ph.p_flags);
    const first_page = ph.p_vaddr & ~(paging.page_size - 1);
    const last_page = (ph.p_vaddr + ph.p_memsz + paging.page_size - 1) & ~(paging.page_size - 1);

    var page = first_page;
    while (page < last_page) : (page += paging.page_size) {
        const page_end = page + paging.page_size;
        const seg_start = @max(page, ph.p_vaddr);
        const seg_end = @min(page_end, ph.p_vaddr + ph.p_memsz);

        const page_buf: []u8 = if (paging.getPhysIn(cr3, page)) |mapped_phys| blk: {
            if (page_ref.count(mapped_phys) == 0) page_ref.retain(mapped_phys) catch return LoadError.OutOfMemory;
            break :blk @as([*]u8, @ptrFromInt(address.physToVirt(mapped_phys)))[0..paging.page_size];
        } else blk: {
            const phys = physical.allocPage() catch return LoadError.OutOfMemory;
            const buf = @as([*]u8, @ptrFromInt(address.physToVirt(phys)))[0..paging.page_size];
            @memset(buf, 0);
            paging.mapUserPageIn(cr3, page, phys, flags) catch return LoadError.OutOfMemory;
            page_ref.retain(phys) catch return LoadError.OutOfMemory;
            break :blk buf;
        };

        if (seg_start < seg_end) {
            const seg_off = seg_start - ph.p_vaddr;
            const page_off = seg_start - page;
            if (seg_off < ph.p_filesz) {
                const file_end = @min(seg_end - ph.p_vaddr, ph.p_filesz);
                const copy_len = file_end - seg_off;
                @memcpy(page_buf[page_off..][0..copy_len], image[ph.p_offset + seg_off ..][0..copy_len]);
            }
        }

        if (paging.getPhysIn(cr3, page) != null) {
            const current = paging.getPageFlagsIn(cr3, page) orelse flags;
            const merged = mergeSegmentPageFlags(current, flags);
            paging.setPageFlagsIn(cr3, page, merged) catch return LoadError.OutOfMemory;
        }
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
            paging.Pte.user_heap,
        ) catch return LoadError.OutOfMemory;
        page_ref.retain(phys) catch return LoadError.OutOfMemory;
    }

    return user_stack_top;
}

fn writeUserU64(cr3: u64, virt: u64, value: u64) LoadError!void {
    const page = virt & ~(paging.page_size - 1);
    const off = virt & (paging.page_size - 1);
    const phys = paging.getPhysIn(cr3, page) orelse return LoadError.OutOfMemory;
    const page_virt = address.physToVirt(phys);
    const base: [*]u8 = @ptrFromInt(page_virt);
    const ptr: *u64 = @ptrCast(@alignCast(base + off));
    ptr.* = value;
}

fn writeUserBytes(cr3: u64, virt: u64, data: []const u8) LoadError!void {
    var written: usize = 0;
    while (written < data.len) {
        const addr = virt + written;
        const page = addr & ~(paging.page_size - 1);
        const off = addr & (paging.page_size - 1);
        const phys = paging.getPhysIn(cr3, page) orelse return LoadError.OutOfMemory;
        const page_virt = address.physToVirt(phys);
        const chunk = @min(data.len - written, paging.page_size - off);
        @memcpy(@as([*]u8, @ptrFromInt(page_virt))[off .. off + chunk], data[written .. written + chunk]);
        written += chunk;
    }
}

fn writeUserByte(cr3: u64, virt: u64, byte: u8) LoadError!void {
    try writeUserBytes(cr3, virt, &.{byte});
}

fn pushInitialStack(
    cr3: u64,
    stack_top: u64,
    argv: []const []const u8,
    envp: []const []const u8,
) LoadError!u64 {
    if (argv.len > max_argv or envp.len > max_envp) return LoadError.OutOfMemory;

    var sp = stack_top & ~@as(u64, 15);
    var env_ptrs: [max_envp]u64 = undefined;
    var arg_ptrs: [max_argv]u64 = undefined;

    var i = envp.len;
    while (i > 0) {
        i -= 1;
        const entry = envp[i];
        if (entry.len >= max_string_len) return LoadError.OutOfMemory;
        if (sp < entry.len + 16) return LoadError.OutOfMemory;
        sp -= entry.len + 1;
        sp &= ~@as(u64, 7);
        try writeUserBytes(cr3, sp, entry);
        try writeUserByte(cr3, sp + entry.len, 0);
        env_ptrs[i] = sp;
    }

    i = argv.len;
    while (i > 0) {
        i -= 1;
        const arg = argv[i];
        if (arg.len >= max_string_len) return LoadError.OutOfMemory;
        if (sp < arg.len + 16) return LoadError.OutOfMemory;
        sp -= arg.len + 1;
        sp &= ~@as(u64, 7);
        try writeUserBytes(cr3, sp, arg);
        try writeUserByte(cr3, sp + arg.len, 0);
        arg_ptrs[i] = sp;
    }

    sp -= 8;
    sp &= ~@as(u64, 7);
    try writeUserU64(cr3, sp, 0);

    i = envp.len;
    while (i > 0) {
        i -= 1;
        sp -= 8;
        try writeUserU64(cr3, sp, env_ptrs[i]);
    }

    sp -= 8;
    try writeUserU64(cr3, sp, 0);

    i = argv.len;
    while (i > 0) {
        i -= 1;
        sp -= 8;
        try writeUserU64(cr3, sp, arg_ptrs[i]);
    }

    sp -= 8;
    try writeUserU64(cr3, sp, argv.len);

    return sp;
}
