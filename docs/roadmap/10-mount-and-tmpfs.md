# Phase 10 — Mount and tmpfs

**Goal:** Multi-mount VFS, RAM-backed tmpfs at `/tmp`, mount API, and fuller VFS operations — with FAT32 as the only on-disk filesystem.

**Depends on:** [Phase 9 — Virtual memory and page cache](09-virtual-memory-and-page-cache.md) (buffered I/O), [Phase 8 — Process environment](08-process-environment.md) (kernel cwd, `/dev`)

**Unlocks:** [Phase 11 — procfs and sysfs](11-procfs-and-sysfs.md) (reuse mount + pseudo-fs plumbing)

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

- [ ] VFS mount points (attach fs instance to path prefix)
- [ ] Syscall: `mount` / `umount`
- [ ] Document mount order: FAT root → tmpfs on `/tmp`
- [ ] Root `getdents` synthesizes `tmp` (same pattern as `dev`)

### tmpfs

- [ ] RAM-backed `Ops` (grow/shrink with heap or page allocator)
- [ ] Mount at `/tmp` at boot
- [ ] Files disappear on reboot — document behavior
- [ ] Integration test: write `/tmp/foo`, read in same session; gone after reboot

### Permissions (light)

- [ ] Mode bits stored on tmpfs nodes at create (default permissive)
- [ ] FAT: document “no Unix permissions on disk”
- [ ] No full `chmod` / credential model in this phase

### VFS completeness

- [ ] `rename` on FAT and tmpfs
- [ ] `symlink` + `readlink` on tmpfs only (FAT → `ENOTSUP`)
- [ ] `fsync` continues to flush dirty pages through page cache (FAT)
- [ ] Document which ops FAT vs tmpfs vs `/dev` support

### Page cache

- [ ] Per-handle / per-mount `Ops` for multi-mount writeback (not a single global binder)

---

## Acceptance criteria

1. **tmpfs mounts** at `/tmp`; shell and programs can create ephemeral files.
2. **FAT boot disk unchanged** — `/BIN/*` still loads from existing workflow.
3. **`mount` / `umount`** work for tmpfs (root FAT remains mounted).
4. **`rename`** works on FAT and tmpfs; **`symlink` / `readlink`** work on tmpfs.
5. Host + integration tests cover mount resolve and tmpfs round-trip (ephemeral across reboot).

---

## Capability matrix (fill in as implemented)

| Op | FAT | tmpfs | `/dev` |
|----|-----|-------|--------|
| open / read / write | yes | yes | devices via special FDs |
| mkdir / rmdir / unlink | yes | yes | no |
| rename | yes | yes | no |
| symlink / readlink | no | yes | no |
| fsync | yes (page cache) | n/a or no-op | n/a |
| Unix mode bits | no | create-time only | n/a |

---

## Notes

- tmpfs is the proving ground for pseudo filesystems before `/proc` ([phase 11](11-procfs-and-sysfs.md)).
- Page cache from [phase 9](09-virtual-memory-and-page-cache.md) must support more than one `Ops` backend once tmpfs is mounted.
- No second on-disk format: FAT remains the interoperability and boot volume.
