# Phase 5 — I/O stack

**Goal:** Block storage, a filesystem, and basic networking over VirtIO (or equivalent QEMU devices).

**Depends on:** [Phase 4 — Userspace](04-userspace.md)

**Unlocks:** [Phase 6 — SMP and GUI](06-smp-and-gui.md)

---

## Checklist

- [x] Add PCI enumeration helper ([`drivers/pci.zig`](../../kernel/drivers/pci.zig))
- [x] Add block device driver
  - [x] VirtIO-blk **or** ATA/AHCI for QEMU
  - [x] Read/write sectors
- [x] Add [`fs/vfs.zig`](../../kernel/fs/vfs.zig)
  - [x] Vnode/inode interface
  - [x] Path lookup and file descriptors wired to syscalls
- [x] Add filesystem implementation
  - [x] FAT32 first (aligns with boot volume), **or** ext2
  - [x] `open`, `read`, `close` via VFS
- [x] Extend syscalls: `open`, `close`, `lseek`, `stat` (minimal subset)
- [x] FAT32 write/create/truncate/append; files persist across reboot (same `disk.img`)
- [x] Shell builtins: `cat`, `ls`, `write` (with `-a` append)
- [x] Add network device driver
  - [x] VirtIO-net **or** e1000
  - [x] TX/RX ring handling
- [x] Add [`net/`](../../kernel/net/)
  - [x] Ethernet frame TX/RX
  - [x] ARP
  - [x] IPv4
  - [x] UDP
  - [x] ICMP echo
  - [x] TCP (minimal: connect, send, recv, close)
- [x] Add socket syscalls: `socket`, `bind`, `connect`, `send`, `recv`, `sendto`, `recvfrom`, `close`
- [x] Add network inspection syscalls for `ip addr`, `ip route`, and `ip neigh`
- [x] Userland tests: `ping`, DNS (`dig`/codec), and HTTP GET over TCP via `curl`
- [ ] Improve `ping` output with multiple packets, RTT, packet loss, and summary stats

---

## Acceptance criteria

1. **Read a file from disk via VFS** — user program opens `/path` and reads bytes correctly.
2. **Write/create file** persists across reboot (same virtual disk image).
3. **Syscall file I/O** matches POSIX-ish behavior for the implemented subset.
4. **Network driver sends and receives frames** — ARP and ping succeed on QEMU user networking.
5. **TCP connection** to a host service (e.g. QEMU's built-in services or a local test server) completes a round-trip via `curl`.
6. **Kernel remains stable** under concurrent file and network activity from userspace.

---

## Notes

- Prefer one device type per category and stick with it for QEMU (`-device virtio-blk-pci`, `-device virtio-net-pci`).
- TCP can start as a minimal implementation; full POSIX socket edge cases come later.
- Current userspace network tools are intentionally small: `ip` for local network state, `dig` for DNS, `ping` for ICMP, and `curl` for HTTP over TCP.
