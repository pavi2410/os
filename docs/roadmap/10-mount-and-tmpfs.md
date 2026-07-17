# Phase 10 — Mount and tmpfs

**Goal:** Multi-mount VFS, RAM-backed tmpfs at `/tmp`, mount API, and fuller VFS operations — with FAT32 as the only on-disk filesystem.

**Depends on:** [Phase 9 — Virtual memory and page cache](09-virtual-memory-and-page-cache.md) (buffered I/O), [Phase 8 — Process environment](08-process-environment.md) (kernel cwd, `/dev`)

**Unlocks:** [Phase 11 — procfs and sysfs](11-procfs-and-sysfs.md) (reuse mount + pseudo-fs plumbing)

**Status:** Done

---

## Scope decisions

| Filesystem | In scope | Out of scope |
|------------|----------|--------------|
| **FAT32** | Sole on-disk FS for boot `disk.img` and `/BIN` | — |
| **tmpfs** | Yes — RAM files under `/tmp` | — |
| **ext2 / ext3 / ext4 / btrfs / ZFS** | No | Not planned; FAT covers persistence and interoperability |
| **Second disk / partitions** | No | Software mounts only |

`/dev` stays today’s path special-case + device FDs (not converted to a full `Ops` mount in this phase).

---

## Checklist

### Mount API

- [x] VFS mount points (attach fs instance to path prefix)
- [x] Syscall: `mount` / `umount2`
- [x] Document mount order: FAT root → tmpfs on `/tmp`
- [x] Root `getdents` synthesizes `tmp` (same pattern as `dev`)

### tmpfs

- [x] RAM-backed `Ops` (fixed node/data pools)
- [x] Mount at `/tmp` at boot
- [x] Files disappear on reboot — documented below
- [x] Integration test: write `/tmp/foo`, read in same session; gone after reboot

### Permissions (light)

- [x] Mode bits stored on tmpfs nodes at create (default permissive)
- [x] FAT: no Unix permissions on disk (documented in matrix)
- [x] No full `chmod` / credential model in this phase

### VFS completeness

- [x] `rename` on FAT and tmpfs
- [x] `symlink` + `readlink` on tmpfs only (FAT → `ENOTSUP`)
- [x] `fsync` continues to flush dirty pages through page cache (FAT)
- [x] Document which ops FAT vs tmpfs vs `/dev` support

### Page cache

- [x] Per-handle / per-mount `Ops` for multi-mount writeback (ops pointer on cache key)

---

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | tmpfs mounts at `/tmp`; shell and programs can create ephemeral files | **Done** |
| 2 | FAT boot disk unchanged — `/BIN/*` still loads | **Done** |
| 3 | `mount` / `umount2` work for tmpfs (root FAT remains mounted) | **Done** (`mounttest`) |
| 4 | `rename` on FAT and tmpfs; `symlink` / `readlink` on tmpfs | **Done** (`linktest`) |
| 5 | Host + integration tests cover mount resolve and tmpfs round-trip | **Done** |

---

## Capability matrix

| Op | FAT | tmpfs | `/dev` |
|----|-----|-------|--------|
| open / read / write | yes | yes (not on symlinks) | devices via special FDs |
| mkdir / rmdir / unlink | yes | yes | no |
| rename | yes | yes | no |
| symlink / readlink | no (`ENOTSUP`) | yes | no |
| fsync | yes (page cache) | no-op via empty cache | n/a |
| Unix mode bits | no | create-time only | n/a |
| mount / umount | root (permanent) | yes (singleton) | n/a |

**Ephemeral tmpfs:** contents live only in RAM. A reboot (or `umount` + remount / remount reset) discards all files under `/tmp`.

**Mount order at boot:** FAT at `/`, then tmpfs at `/tmp`. `/dev` remains a path special-case.

---

## Notes

- tmpfs is the proving ground for pseudo filesystems before `/proc` ([phase 11](11-procfs-and-sysfs.md)).
- Page cache keys include the filesystem `Ops` pointer so writeback targets the correct backend.
- No second on-disk format: FAT remains the interoperability and boot volume.
