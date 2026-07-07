# Syscall ABI (x86_64)

This kernel uses the **Linux x86_64 syscall convention** so user programs and a future libc can share the same interface as Phase 4 userspace.

## Mechanism

- Entry: `syscall` instruction → `LSTAR` (`syscall_entry`)
- Return: `sysret` for ring-3 callers; ring-0 test callers return via restored `RFLAGS` + `jmp` to the saved `RCX`
- MSRs: `EFER.SCE`, `STAR`, `LSTAR`, `SFMASK` (interrupt flag cleared on entry)

## Register convention

| Role | Register |
|------|----------|
| Syscall number | `RAX` |
| Arg 1 | `RDI` |
| Arg 2 | `RSI` |
| Arg 3 | `RDX` |
| Arg 4 | `R10` |
| Arg 5 | `R8` |
| Arg 6 | `R9` |
| Return value | `RAX` |
| Preserved by kernel on entry | `RCX` = user return RIP, `R11` = user RFLAGS |

Negative `RAX` values follow the Linux errno convention (e.g. `-38` = `ENOSYS`).

## Implemented syscalls

| Number | Name | Notes |
|--------|------|-------|
| 0 | `read` | File/console read |
| 1 | `write` | `fd` 1 or 2 → serial; returns bytes written |
| 2 | `open` | VFS open |
| 3 | `close` | Close file descriptor |
| 4 | `stat` | Minimal stat metadata |
| 8 | `lseek` | File offset seek |
| 12 | `brk` | Userspace heap break |
| 39 | `getpid` | Current process ID |
| 41 | `socket` | `AF_INET` datagram/stream sockets |
| 42 | `connect` | TCP client connect |
| 44 | `sendto` | Datagram send |
| 45 | `recvfrom` | Datagram receive |
| 46 | `send` | Connected socket send |
| 47 | `recv` | Connected socket receive |
| 49 | `bind` | Bind socket address |
| 57 | `fork` | Duplicate process |
| 59 | `execve` | Replace process image |
| 60 | `exit` | Terminates current thread; does not return |
| 61 | `wait4` | Reap child process |
| 83 | `mkdir` | Create directory |
| 84 | `rmdir` | Remove directory |
| 87 | `unlink` | Remove file |
| 217 | `getdents64` | Directory entries |
| 228 | `clock_gettime` | Realtime/monotonic clocks |
| 231 | `exit_group` | Process exit |
| 1024 | `getnetconfig` | Kernel network config snapshot for `ip addr`/`ip route` |
| 1025 | `getneighbors` | ARP/neighbor table snapshot for `ip neigh` |
| 1026 | `getcpuinfo` | CPU identification snapshot for `lscpu` |
| 1027 | `getpcidevices` | PCI device table snapshot for `lspci` |
| 1028 | `getblockdevices` | Block device table snapshot for `lsblk` |
| 1029 | `getmemregions` | Physical memory map snapshot for `lsmem` |

## Segments

GDT selectors used by `STAR`:

| Selector | Purpose |
|----------|---------|
| `0x08` | Kernel code (syscall entry) |
| `0x10` | Kernel data |
| `0x18` | User code (`sysret`) |
| `0x20` | User data (`sysret` SS = user code + 8) |

## Testing

`kernel/syscall/test.zig` runs from a kernel thread at ring 0 (roadmap “simulated user stack” style): it calls `write` and verifies the return path, then terminates via `exit`. Ring-3 stubs can reuse the same entry stub’s `sysret` path once user page tables and TSS are wired for Phase 4.
