const std = @import("std");
const uefi = std.os.uefi;
const elf = std.elf;

const uefi_utils = @import("uefi.zig");

pub const ElfLoadError = error{
    InvalidElf,
    UnsupportedArchitecture,
    FileNotFound,
    ReadError,
    OutOfMemory,
};

pub const LoadedElf = struct {
    entry_point: u64,
    load_base: u64,
};

/// Load an ELF file from the filesystem
pub fn loadKernel(kernel_path: [*:0]const u16) ElfLoadError!LoadedElf {
    const boot_services = uefi.system_table.boot_services.?;

    // Open the loaded image protocol to get the device handle
    const loaded_image = boot_services.openProtocol(
        uefi.protocol.LoadedImage,
        uefi.handle,
        .{ .get_protocol = .{ .agent = uefi.handle, .controller = null } },
    ) catch {
        uefi_utils.printf("Failed to open LoadedImage protocol\r\n", .{});
        return ElfLoadError.FileNotFound;
    } orelse {
        uefi_utils.printf("LoadedImage protocol returned null\r\n", .{});
        return ElfLoadError.FileNotFound;
    };

    // Open the Simple File System protocol
    const device_handle = loaded_image.device_handle orelse {
        uefi_utils.printf("LoadedImage has no device handle\r\n", .{});
        return ElfLoadError.FileNotFound;
    };

    const file_system = boot_services.openProtocol(
        uefi.protocol.SimpleFileSystem,
        device_handle,
        .{ .get_protocol = .{ .agent = uefi.handle, .controller = null } },
    ) catch {
        uefi_utils.printf("Failed to open SimpleFileSystem protocol\r\n", .{});
        return ElfLoadError.FileNotFound;
    } orelse {
        uefi_utils.printf("SimpleFileSystem protocol returned null\r\n", .{});
        return ElfLoadError.FileNotFound;
    };

    // Open the root directory
    const root = file_system.openVolume() catch {
        uefi_utils.printf("Failed to open root volume\r\n", .{});
        return ElfLoadError.FileNotFound;
    };

    // Open the kernel file
    const kernel_file = root.open(
        kernel_path,
        .read,
        .{},
    ) catch {
        uefi_utils.printf("Failed to open kernel file\r\n", .{});
        return ElfLoadError.FileNotFound;
    };

    // Get file size
    var file_info_buffer: [256]u8 align(@alignOf(uefi.protocol.File.Info.File)) = undefined;
    const file_info = kernel_file.getInfo(.file, &file_info_buffer) catch {
        uefi_utils.printf("Failed to get file info\r\n", .{});
        return ElfLoadError.FileNotFound;
    };

    const file_size = file_info.file_size;

    uefi_utils.printf("Kernel file size: {d} bytes\r\n", .{file_size});

    // Allocate memory for the file
    const file_buffer = boot_services.allocatePool(uefi.tables.MemoryType.loader_data, file_size) catch {
        uefi_utils.printf("Failed to allocate memory for kernel file\r\n", .{});
        return ElfLoadError.OutOfMemory;
    };

    // Read the file
    const read_size = kernel_file.read(file_buffer) catch {
        uefi_utils.printf("Failed to read kernel file\r\n", .{});
        return ElfLoadError.ReadError;
    };

    if (read_size != file_size) {
        uefi_utils.printf("Partial read: got {d} bytes, expected {d}\r\n", .{ read_size, file_size });
        return ElfLoadError.ReadError;
    }

    kernel_file.close() catch {};
    root.close() catch {};

    uefi_utils.printf("Kernel file read successfully\r\n", .{});

    // Parse and load the ELF file
    return parseAndLoadElf(file_buffer);
}

fn parseAndLoadElf(file_buffer: []align(8) u8) ElfLoadError!LoadedElf {
    const boot_services = uefi.system_table.boot_services.?;

    // Verify ELF magic number
    if (file_buffer.len < 4 or !std.mem.eql(u8, file_buffer[0..4], elf.MAGIC)) {
        uefi_utils.printf("Invalid ELF magic number\r\n", .{});
        return ElfLoadError.InvalidElf;
    }

    // Parse ELF header
    const ehdr: *elf.Elf64_Ehdr = @ptrCast(@alignCast(file_buffer.ptr));

    // Verify it's a 64-bit ELF
    if (file_buffer[elf.EI_CLASS] != elf.ELFCLASS64) {
        uefi_utils.printf("Not a 64-bit ELF\r\n", .{});
        return ElfLoadError.InvalidElf;
    }

    // Verify it's x86_64
    if (ehdr.e_machine != elf.EM.X86_64) {
        uefi_utils.printf("Not an x86_64 ELF\r\n", .{});
        return ElfLoadError.UnsupportedArchitecture;
    }

    uefi_utils.printf("ELF entry point: 0x{x}\r\n", .{ehdr.e_entry});
    uefi_utils.printf("Program headers: {d} at offset 0x{x}\r\n", .{ ehdr.e_phnum, ehdr.e_phoff });

    var load_base: u64 = 0xFFFFFFFF_FFFFFFFF;
    var load_end: u64 = 0;

    // First pass: find the load address range
    for (0..ehdr.e_phnum) |i| {
        const phdr_offset = ehdr.e_phoff + i * ehdr.e_phentsize;
        const phdr: *elf.Elf64_Phdr = @ptrCast(@alignCast(file_buffer.ptr + phdr_offset));

        if (phdr.p_type == elf.PT_LOAD) {
            if (phdr.p_paddr < load_base) {
                load_base = phdr.p_paddr;
            }
            const segment_end = phdr.p_paddr + phdr.p_memsz;
            if (segment_end > load_end) {
                load_end = segment_end;
            }
        }
    }

    if (load_base == 0xFFFFFFFF_FFFFFFFF) {
        uefi_utils.printf("No loadable segments found\r\n", .{});
        return ElfLoadError.InvalidElf;
    }

    const total_size = load_end - load_base;
    uefi_utils.printf("Kernel load range: 0x{x} - 0x{x} ({d} bytes)\r\n", .{ load_base, load_end, total_size });

    // Allocate pages for the kernel - try at requested address first, then anywhere
    const page_count = (total_size + 0xFFF) / 0x1000;

    var pages_result = boot_services.allocatePages(
        .{ .address = @ptrFromInt(load_base) },
        .loader_data,
        page_count,
    );

    if (pages_result) |_| {
        uefi_utils.printf("Successfully allocated at requested address\r\n", .{});
    } else |_| {
        uefi_utils.printf("Failed to allocate at requested address 0x{x}\r\n", .{load_base});
        uefi_utils.printf("Trying to allocate anywhere below 4GB...\r\n", .{});

        // Try allocating below 4GB as a fallback
        pages_result = boot_services.allocatePages(
            .{ .max_address = @ptrFromInt(0x100000000) },
            .loader_data,
            page_count,
        );
    }

    const pages = pages_result catch {
        uefi_utils.printf("Failed to allocate {d} pages\r\n", .{page_count});
        return ElfLoadError.OutOfMemory;
    };

    const physical_addr = @intFromPtr(pages.ptr);

    uefi_utils.printf("Allocated {d} pages at 0x{x}\r\n", .{ page_count, physical_addr });

    // Verify we got the requested address
    if (physical_addr != load_base) {
        uefi_utils.printf("ERROR: Allocated at 0x{x} but kernel expects 0x{x}\r\n", .{ physical_addr, load_base });
        uefi_utils.printf("Kernel is position-dependent and cannot be relocated!\r\n", .{});
        return ElfLoadError.OutOfMemory;
    }

    // Zero out the allocated memory
    const bytes: [*]u8 = @ptrCast(pages.ptr);
    @memset(bytes[0 .. page_count * 4096], 0);

    // Second pass: load the segments at their specified addresses
    for (0..ehdr.e_phnum) |i| {
        const phdr_offset = ehdr.e_phoff + i * ehdr.e_phentsize;
        const phdr: *elf.Elf64_Phdr = @ptrCast(@alignCast(file_buffer.ptr + phdr_offset));

        if (phdr.p_type == elf.PT_LOAD) {
            const dest_addr = phdr.p_paddr;
            const dest: [*]u8 = @ptrFromInt(dest_addr);
            const src = file_buffer.ptr + phdr.p_offset;

            uefi_utils.printf("Loading segment: 0x{x} ({d} bytes, {d} in memory)\r\n", .{
                dest_addr,
                phdr.p_filesz,
                phdr.p_memsz,
            });

            // Copy file data
            @memcpy(dest[0..phdr.p_filesz], src[0..phdr.p_filesz]);

            // Zero out BSS if memsz > filesz
            if (phdr.p_memsz > phdr.p_filesz) {
                @memset(dest[phdr.p_filesz..phdr.p_memsz], 0);
            }
        }
    }

    uefi_utils.printf("Kernel loaded successfully\r\n", .{});

    return LoadedElf{
        .entry_point = ehdr.e_entry,
        .load_base = physical_addr,
    };
}
