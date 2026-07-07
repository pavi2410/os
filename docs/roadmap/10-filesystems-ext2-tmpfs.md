# Phase 10 — Filesystems: ext2, mount, tmpfs

**Goal:** Add a second on-disk filesystem (ext2), a RAM-backed tmpfs, mount API, Unix permissions, and fuller VFS operations.

**Depends on:** [Phase 9 — Virtual memory and page cache](09-virtual-memory-and-page-cache.md) (buffered I/O), [Phase 8 — Process environment](08-process-environment.md) (kernel cwd, `/dev`)

**Unlocks:** [Phase 11 — procfs and sysfs](11-procfs-and-sysfs.md) (reuse pseudo-fs and mount plumbing)

---

## Scope decisions

| Filesystem | In scope | Out of scope (deferred) |
|------------|----------|-------------------------|
| **FAT32** | Keep for boot `disk.img` and `/BIN` | — |
| **ext2** | Yes — first "Unix" FS | ext3/ext4 journaling |
| **tmpfs** | Yes — RAM files under `/tmp` or `/run` | — |
| **ext4 / btrfs / ZFS** | No | Multi-year efforts; revisit only after ext2 is boring |

---

## Checklist

### Mount API

- [ ] VFS mount points (attach fs instance to path prefix)
- [ ] Syscall: `mount` / `umount` (or minimal custom mount for init first)
- [ ] Second block device or partition for ext2 test image (QEMU config + `disk.img` layout decision)
- [ ] Document mount order: FAT root → optional ext2 data partition → tmpfs on `/tmp`
- [ ] Block device nodes in `/dev` for mount targets

### ext2

- [ ] Read superblock, block group descriptors, inode tables
- [ ] Path lookup, `readdir`, `read` (via page cache from phase 9)
- [ ] Write path: create, unlink, truncate, append (match FAT feature set first)
- [ ] Host unit tests for on-disk structures (use fixture images in `test/fixtures/`)
- [ ] Integration test: create file on ext2, reboot or remount, read back

### tmpfs

- [ ] RAM-backed vnode ops (grow/shrink with heap or page allocator)
- [ ] Mount at `/tmp` (and optionally `/run`)
- [ ] Files disappear on reboot — document behavior
- [ ] Integration test: write `/tmp/foo`, read in same session; gone after reboot

### Permissions and identity

- [ ] `uid`/`gid` on process (start with root-only if needed, but store fields)
- [ ] ext2 inode mode bits (`owner/group/other` rwx)
- [ ] Syscalls: `getuid`, `getgid`, `geteuid`, `getegid` (minimal set)
- [ ] Syscalls: `chmod`, `umask` (or `fchmod` subset)
- [ ] `open`/`access` checks against file mode (even if all processes run as root initially)
- [ ] Document deviation from full Linux capability model

### VFS completeness

- [ ] `rename` (atomic where FS supports it)
- [ ] `link` (hard links on ext2)
- [ ] `symlink` + `readlink`
- [ ] `fsync` / `fdatasync` — flush dirty pages through page cache to disk
- [ ] Document which ops FAT vs ext2 support

### Build / disk tooling

- [ ] Script or mise task to create ext2 test partition
- [ ] Update [`scripts/create_disk.py`](../../scripts/create_disk.py) docs if layout changes

---

## Acceptance criteria

1. **ext2 volume mounts** at a path prefix; `cat`, `write`, `ls` work through VFS.
2. **tmpfs mounts** at `/tmp`; shell and programs can create ephemeral files.
3. **FAT boot disk unchanged** — `/BIN/*` still loads from existing workflow.
4. **Permission bits** stored and checked on ext2 (at least owner read/write).
5. **`rename` and `symlink`** work on ext2; integration test covers round-trip.
6. **`fsync`** persists data across remount or reboot on ext2 test image.
7. Host + integration tests cover ext2 superblock parse and tmpfs round-trip.

---

## Notes

- ext2 before ext4: same VFS lessons, far less complexity (no journal, no extents).
- tmpfs is a good proving ground for pseudo filesystems before `/proc` ([phase 11](11-procfs-and-sysfs.md)).
- Page cache from [phase 9](09-virtual-memory-and-page-cache.md) should be wired before ext2 read performance matters.
