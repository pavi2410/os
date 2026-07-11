const fat32 = @import("../fs/fat32.zig");
const heap = @import("../mm/heap.zig");
const vfs = @import("../fs/vfs.zig");
const runtime = @import("../runtime.zig");

pub const LoadError = error{
    NotReady,
    NotFound,
    NotFile,
    TooLarge,
    OutOfMemory,
    IoError,
    PathTooLong,
};

/// Maximum ELF image size read from the VirtIO FAT volume.
const max_image_size = 256 * 1024;

const bin_dir = "/BIN/";
const init_shell_path = "/BIN/SHELL";

/// Path to the init shell on the VirtIO FAT volume.
pub fn initShellPath() []const u8 {
    return init_shell_path;
}

/// Read a program ELF from the mounted FAT32 volume (exact path only).
pub fn load(path: []const u8) LoadError![]u8 {
    return loadAt(path);
}

fn loadAt(path: []const u8) LoadError![]u8 {
    if (!runtime.boot().vfs.isReady()) return LoadError.NotReady;

    const entry = fat32.lookup(path) catch |err| switch (err) {
        fat32.FatError.NotFound => return LoadError.NotFound,
        fat32.FatError.NotReady => return LoadError.NotReady,
        fat32.FatError.IsDirectory => return LoadError.NotFile,
        fat32.FatError.PathTooLong => return LoadError.PathTooLong,
        else => return LoadError.IoError,
    };
    if (entry.attr & 0x10 != 0) return LoadError.NotFile;
    if (entry.size == 0 or entry.size > max_image_size) return LoadError.TooLarge;

    const mem = heap.kmalloc(entry.size) catch return LoadError.OutOfMemory;
    errdefer heap.kfree(mem) catch {};

    const buf: []u8 = mem[0..entry.size];
    const n = fat32.read(entry, 0, buf) catch {
        return LoadError.IoError;
    };
    if (n != entry.size) return LoadError.IoError;

    return buf;
}

pub fn free(image: []u8) void {
    if (image.len == 0) return;
    heap.kfree(image.ptr) catch {};
}
