# Phase 5 — I/O stack

**Goal:** Block storage, a filesystem, and basic networking over VirtIO (or equivalent QEMU devices).

**Depends on:** [Phase 4 — Userspace](04-userspace.md)

**Unlocks:** [Phase 6 — Testing and quality](06-testing-and-quality.md) and later phases

**Status:** Done for current goals. TCP hardening is deferred (see [backlog](README.md#deferred-backlog-not-scheduled)).

---

## Checklist

### Block and VFS

- [x] Add PCI enumeration helper ([`drivers/pci.zig`](../../kernel/drivers/pci.zig))
- [x] Add block device driver
  - [x] VirtIO-blk for QEMU
  - [x] Read/write sectors
- [x] Add [`fs/vfs.zig`](../../kernel/fs/vfs.zig)
  - [x] Vnode/inode interface
  - [x] Path lookup and file descriptors wired to syscalls
- [x] Add filesystem implementation
  - [x] FAT32 (boot volume and `disk.img`)
  - [x] `open`, `read`, `close` via VFS
- [x] Extend syscalls: `open`, `close`, `lseek`, `stat` (minimal subset)
- [x] FAT32 write/create/truncate/append; files persist across reboot (same `disk.img`)
- [x] Shell builtins: `cat`, `ls`, `write` (with `-a` append), `cd`/`pwd`, `rm`, `mkdir`, `rmdir`
- [x] Split FAT32 into [`core` / `path` / `dir` / `file`](../../kernel/fs/fat32/) modules

### Networking

- [x] Add network device driver (VirtIO-net)
  - [x] TX/RX ring handling
- [x] Add [`net/`](../../kernel/net/)
  - [x] Ethernet frame TX/RX
  - [x] ARP, IPv4, UDP, ICMP echo
  - [x] TCP (minimal client: connect, send, recv, close)
- [x] Socket syscalls: `socket`, `bind`, `connect`, `send`, `recv`, `sendto`, `recvfrom`, `close`
- [x] Network inspection syscalls: `getnetconfig`, `getneighbors` (for `ip addr` / `route` / `neigh`)
- [x] Userland: `ping`, `dig` (DNS codec), `curl` (HTTP over TCP), `ip`
- [x] `ping` with multiple packets, RTT, packet loss, and summary stats

### Hardware introspection (interim)

Bootstrap syscalls and tools until [procfs](11-procfs-and-sysfs.md) replaces them:

- [x] Shared ABI: [`common/abi/hw.zig`](../../common/abi/hw.zig) (`extern struct`, comptime layout checks)
- [x] Syscalls: `getcpuinfo`, `getpcidevices`, `getblockdevices`, `getmemregions`
- [x] Kernel fill + CR3-aware copy-out ([`kernel/syscall/copy_out.zig`](../../kernel/syscall/copy_out.zig))
- [x] Userland: `lscpu`, `lspci`, `lsblk`, `lsmem`

---

## Acceptance criteria

1. **Read a file from disk via VFS** — user program opens `/path` and reads bytes correctly.
2. **Write/create file** persists across reboot (same virtual disk image).
3. **Syscall file I/O** matches POSIX-ish behavior for the implemented subset.
4. **Network driver sends and receives frames** — ARP and ping succeed on QEMU user networking.
5. **TCP connection** to a host service completes a round-trip via `curl`.
6. **Hardware tools** — `lscpu`, `lspci`, `lsblk`, `lsmem` run from the shell without crashing the VM.

All criteria met.

---

## Deferred (phase 5 backlog)

- [ ] **TCP/IP hardening** — repeated/concurrent connections, error paths, resource limits under load
- [ ] **Listen/accept** — TCP server sockets (not required for current `curl` client use case)
- [ ] **UDP socket polish** — edge cases beyond DNS/`dig`

---

## Notes

- Prefer one device type per category for QEMU (`virtio-blk-pci`, `virtio-net-pci`).
- Minimal TCP is sufficient for now; hardening is explicitly deferred.
- Hardware snapshot syscalls are a stepping stone; migrate to `/proc` and `/sys` in [phase 11](11-procfs-and-sysfs.md).
- Do **not** add ext2/ext4, ZFS, or btrfs here — see [phase 10](10-mount-and-tmpfs.md) for mount + tmpfs (FAT remains the only on-disk FS).
