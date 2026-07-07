# Phase 11 — procfs and sysfs

**Goal:** Expose kernel and hardware state as files under `/proc` and `/sys`, replacing bespoke snapshot syscalls with path-based introspection.

**Depends on:** [Phase 10 — Filesystems](10-filesystems-ext2-tmpfs.md) (mount + pseudo-fs pattern)

**Unlocks:** [Phase 13 — SMP](13-smp.md) (cleaner introspection before scaling to multicore)

---

## Motivation

Phase 5 added interim syscalls and tools:

| Syscall | Tool | Future path |
|---------|------|-------------|
| `getcpuinfo` (1026) | `lscpu` | `/proc/cpuinfo` |
| `getpcidevices` (1027) | `lspci` | `/sys/bus/pci/devices/...` or `/proc/bus/pci/...` |
| `getblockdevices` (1028) | `lsblk` | `/sys/block/...` |
| `getmemregions` (1029) | `lsmem` | `/proc/iomem` or `/sys/devices/system/memory/...` |
| `getnetconfig` / `getneighbors` | `ip` | `/proc/net/...` (partial) |

Problems with the syscall approach (already observed in development):

- Shared `extern struct` layout must stay bit-identical across kernel and userspace
- Every new field requires ABI version churn
- Tools cannot use `cat`, `grep`, or shell redirection
- Harder to test than text golden files

---

## Checklist

### Infrastructure

- [ ] Pseudo filesystem type in VFS (seq_file-style read, no persistent storage)
- [ ] Mount `/proc` at boot (init from [phase 8](08-process-environment.md))
- [ ] Optional: mount `/sys` as separate tree or under `/proc/sys`

### `/proc` files (first wave)

- [ ] `/proc/cpuinfo` — replaces `getcpuinfo`
- [ ] `/proc/meminfo` or `/proc/iomem` — replaces `getmemregions` / `lsmem`
- [ ] `/proc/loadavg`, `/proc/uptime` — stretch (timer stats already exist in kernel)
- [ ] `/proc/[pid]/` basics — stretch (`status`, `cmdline`)

### `/sys` or `/proc` device trees

- [ ] PCI device listing — replaces `getpcidevices` / `lspci` text backend
- [ ] Block device listing — replaces `getblockdevices` / `lsblk` text backend

### Userspace migration

- [ ] Rewrite `lscpu`, `lspci`, `lsblk`, `lsmem` as thin `open`/`read` parsers (or `cat` for bootstrap)
- [ ] Deprecate hw snapshot syscalls; document removal in [`syscall-abi.md`](../syscall-abi.md)
- [ ] Keep ABI numbers reserved or return `ENOSYS` after migration

### Network (optional in this phase)

- [ ] `/proc/net/dev`, `/proc/net/arp` — complement `ip` / `getnetconfig`
- [ ] Defer full rtnetlink to long-term backlog

### Tests

- [ ] Golden-file tests for `/proc/cpuinfo` line format (host parse)
- [ ] Integration: `cat /proc/cpuinfo` matches prior `lscpu` fields
- [ ] Integration: `ls` pseudo directory entries

---

## Acceptance criteria

1. **`cat /proc/cpuinfo`** produces vendor, brand, family, model, and CPU count without custom syscalls.
2. **Block and PCI enumeration** available as readable text or directory listings under `/sys` or `/proc`.
3. **`lscpu` / `lsblk` / `lspci` / `lsmem`** use procfs/sysfs only (syscalls removed or stubbed).
4. Integration tests updated; ABI hw structs can shrink or move kernel-private.

---

## Notes

- Text format can follow Linux loosely — document intentional differences.
- Prefer directory + file layout over monolithic ioctls.
- Network config may stay on `getnetconfig` longer if `/proc/net` is deferred — that's acceptable.
