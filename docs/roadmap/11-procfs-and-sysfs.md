# Phase 11 — procfs and sysfs

**Goal:** Expose kernel and hardware state as files under `/proc` and `/sys`, replacing bespoke snapshot syscalls with path-based introspection.

**Depends on:** [Phase 10 — Mount and tmpfs](10-mount-and-tmpfs.md) (mount + pseudo-fs pattern)

**Unlocks:** [Phase 13 — SMP](13-smp.md) (cleaner introspection before scaling to multicore)

**Status:** MVP done (stretch/net deferred)

---

## Motivation

Phase 5 added interim syscalls and tools:

| Syscall | Tool | Path |
|---------|------|------|
| `getcpuinfo` (1026) | `lscpu` | `/proc/cpuinfo` |
| `getpcidevices` (1027) | `lspci` | `/sys/bus/pci/devices/...` |
| `getblockdevices` (1028) | `lsblk` | `/sys/block/...` |
| `getmemregions` (1029) | `lsmem` | `/proc/iomem` |
| `getnetconfig` / `getneighbors` | `ip` | `/proc/net/...` (deferred) |

Problems with the syscall approach (already observed in development):

- Shared `extern struct` layout must stay bit-identical across kernel and userspace
- Every new field requires ABI version churn
- Tools cannot use `cat`, `grep`, or shell redirection
- Harder to test than text golden files

---

## Checklist

### Infrastructure

- [x] Pseudo filesystem type in VFS (seq_file-style read, no persistent storage)
- [x] Mount `/proc` at boot
- [x] Mount `/sys` as a separate tree

### `/proc` files (first wave)

- [x] `/proc/cpuinfo` — replaces `getcpuinfo`
- [x] `/proc/iomem` — replaces `getmemregions` / `lsmem`
- [ ] `/proc/loadavg`, `/proc/uptime` — stretch (timer stats already exist in kernel)
- [ ] `/proc/[pid]/` basics — stretch (`status`, `cmdline`)

### `/sys` device trees

- [x] PCI device listing — `/sys/bus/pci/devices/<BB:DD.F>/{vendor,device,class}`
- [x] Block device listing — `/sys/block/<name>/{size,sector_size}`

### Userspace migration

- [x] Rewrite `lscpu`, `lspci`, `lsblk`, `lsmem` as thin `open`/`read` parsers
- [x] Deprecate hw snapshot syscalls; document removal in [`syscall-abi.md`](../syscall-abi.md)
- [x] Keep ABI numbers reserved; return `ENOSYS`

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

- Text format follows Linux loosely. Intentional extras on `/proc/cpuinfo`: `apic_id`, `ioapic_count`.
- Prefer directory + file layout over monolithic ioctls.
- Network config stays on `getnetconfig` / `getneighbors` until `/proc/net` lands.
