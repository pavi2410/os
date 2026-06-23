# Phase 5 — I/O stack

**Goal:** Block storage, a filesystem, and basic networking over VirtIO (or equivalent QEMU devices).

**Depends on:** [Phase 4 — Userspace](04-userspace.md)

**Unlocks:** [Phase 6 — SMP and GUI](06-smp-and-gui.md)

---

## Checklist

- [ ] Add PCI enumeration helper ([`drivers/pci.zig`](../../src/kernel/drivers/pci.zig))
- [ ] Add block device driver
  - [ ] VirtIO-blk **or** ATA/AHCI for QEMU
  - [ ] Read/write sectors
- [ ] Add [`fs/vfs.zig`](../../src/kernel/fs/vfs.zig)
  - [ ] Vnode/inode interface
  - [ ] Path lookup and file descriptors wired to syscalls
- [ ] Add filesystem implementation
  - [ ] FAT32 first (aligns with boot volume), **or** ext2
  - [ ] `open`, `read`, `close` via VFS
- [ ] Extend syscalls: `open`, `close`, `lseek`, `stat` (minimal subset)
- [ ] Add network device driver
  - [ ] VirtIO-net **or** e1000
  - [ ] TX/RX ring handling
- [ ] Add [`net/`](../../src/kernel/net/)
  - [ ] Ethernet frame TX/RX
  - [ ] ARP
  - [ ] IPv4
  - [ ] UDP
  - [ ] TCP (minimal: connect, send, recv, close)
- [ ] Add socket syscalls: `socket`, `bind`, `connect`, `send`, `recv`, `close`
- [ ] Userland test: `ping`-like tool or static HTTP fetch over TCP (optional stretch)

---

## Acceptance criteria

1. **Read a file from disk via VFS** — user program opens `/path` and reads bytes correctly.
2. **Write/create file** persists across reboot (same virtual disk image).
3. **Syscall file I/O** matches POSIX-ish behavior for the implemented subset.
4. **Network driver sends and receives frames** — ARP and ping (or raw UDP echo) succeeds on QEMU user networking.
5. **TCP connection** to a host service (e.g. QEMU's built-in services or a local test server) completes a round-trip.
6. **Kernel remains stable** under concurrent file and network activity from userspace.

---

## Notes

- Prefer one device type per category and stick with it for QEMU (`-device virtio-blk-pci`, `-device virtio-net-pci`).
- TCP can start as a minimal implementation; full POSIX socket edge cases come later.
- Consider documenting QEMU command-line flags for block/net devices in the README when this phase lands.
