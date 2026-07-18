# Agent guide

Hobby x86-64 OS in Zig. Shared wire/types live in `common/abi/`; kernel and userspace import them via `build.zig` (e.g. `abi_fs`, `abi_net`).

## Typed flags and tags

Do not introduce parallel integer constant bags (`pub const FOO: u32 = N`) for closed sets or bitflags. Prefer Zig types:

- **Closed tag sets** → `enum(uN)` with `fromInt` when decoding raw syscall args (seek whence, dirent type, signal number, address family, mem region kind, clock id).
- **Orthogonal bitflags** with stable bit positions → `packed struct(uN)` plus `fromLinux` / `toLinux` (mmap prot/flags; see also TCP `Flags`, page-table `Pte`).
- Decode raw `u64`/`u32` once at the syscall handler edge; pass typed values inward. Do not thread bare masks through kernel modules.
- **One definition** in `common/abi/` (or another shared common module). Kernel and ulib import it — never redeclare `PROT_*` / `MAP_*` / `AF_*` bags in `userspace/ulib`.
- Temporary `@intFromEnum` aliases (`pub const SEEK_SET = @intFromEnum(Seek.set)`) are fine during migration; new code must use the typed form.
- Sparse Linux open bits (`O_CREAT=0o100`, …) stay numeric at the ABI edge and convert into `filesystem.OpenFlags` — do not invent a packed layout that pretends to be the Linux open word.

### In-repo models

- `kernel/fs/filesystem.zig` — `OpenFlags` (`packed struct`), `Whence` (`enum`)
- `kernel/net/socket/api.zig` — net enums + comptime ABI checks
- `kernel/net/tcp.zig` — `Flags` packed wire flags
- `kernel/arch/x86_64/paging.zig` — `Pte` packed bitfields
