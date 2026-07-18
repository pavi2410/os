# Kernel roadmap

Phased plan for kernel development after the Limine bootloader. Phases 0–5, 7, 9–13 are complete; phases 6, 8, 11 (follow-ups), and 14 are the active forward plan in execution order.

| Phase | Document | Status | Summary |
|-------|----------|--------|---------|
| 0 | [00-foundation.md](00-foundation.md) | Done | Memory map, GDT/IDT, kernel stack |
| 1 | [01-page-tables-and-higher-half-kernel.md](01-page-tables-and-higher-half-kernel.md) | Done | Page tables and higher-half kernel |
| 2 | [02-physical-and-virtual-memory.md](02-physical-and-virtual-memory.md) | Done | Physical, virtual, and heap allocators |
| 3 | [03-kernel-runtime.md](03-kernel-runtime.md) | Done | APIC, timer, threads, scheduler, syscalls |
| 4 | [04-userspace.md](04-userspace.md) | Done | ELF loader, TTY, shell, fork/exec |
| 5 | [05-io-stack.md](05-io-stack.md) | Done | VirtIO block/net, FAT32, sockets, user tools |
| 6 | [06-testing-and-quality.md](06-testing-and-quality.md) | **Next** | Automated tests, ABI guards, CI gate |
| 7 | [07-copy-on-write-fork.md](07-copy-on-write-fork.md) | Done | COW fork, shared pages, fault promotion |
| 8 | [08-process-environment.md](08-process-environment.md) | Planned | Signals, IPC, cwd, env, PATH, init, devfs, TTY |
| 9 | [09-virtual-memory-and-page-cache.md](09-virtual-memory-and-page-cache.md) | Done | `mmap`, demand paging, page cache, W^X |
| 10 | [10-mount-and-tmpfs.md](10-mount-and-tmpfs.md) | Done | mount table, tmpfs, rename/symlink, VFS ops |
| 11 | [11-procfs-and-sysfs.md](11-procfs-and-sysfs.md) | Done | `/proc`, `/sys`; hw snapshot syscalls removed |
| 12 | [12-preemptive-scheduling.md](12-preemptive-scheduling.md) | Done | Involuntary timer preemption (SMP gate) |
| 13 | [13-smp.md](13-smp.md) | Done | Multicore bring-up, ACPI, SMP-safe kernel |
| 14 | [14-gui.md](14-gui.md) | Planned | GOP framebuffer, input, minimal window manager |

**Current focus:** [Phase 6 — Testing and quality](06-testing-and-quality.md)

**Hard gates:** phase 13 (SMP) is done on QEMU `-smp N`. GUI ([phase 14](14-gui.md)) follows.

See also the high-level checklist in the [project README](../../README.md#roadmap).

## Deferred backlog (not scheduled)

Work that is valid but intentionally postponed:

| Item | Notes |
|------|--------|
| TCP/IP hardening | Minimal TCP works (`curl`, `ping`); stress/concurrency polish deferred |
| `listen` / `accept` | TCP server sockets — see [phase 5 backlog](05-io-stack.md#deferred-phase-5-backlog) |
| Linux ABI tier 2 | `poll`/`select`/`epoll`, `clone`/futex/pthreads, dynamic linking (`ld.so`) |
| ext2 / ext4 / btrfs / ZFS | Not planned; FAT is the sole on-disk FS (see [phase 10](10-mount-and-tmpfs.md)) |
| Security hardening | ASLR/KASLR, capabilities, seccomp — after light tmpfs modes (phase 10) |
| Swap / OOM | Optional until memory pressure under real workloads |
| DHCP / `getaddrinfo` | Static IP + `dig` sufficient for now |
| Real hardware bring-up | After QEMU path is solid (ACPI, drivers, SMP) |
