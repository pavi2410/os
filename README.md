# os

**A hobby operating system** in Zig, targeting x86-64 with [Limine](https://github.com/Limine-Bootloader/Limine), aiming for Linux ABI compatibility, multicore support, filesystems, networking, and eventually a GUI.

## Current status

The kernel boots under QEMU, runs a serial shell in userspace, reads files from a VirtIO FAT32 disk, and can spawn embedded ELF programs.

**Working today**

* Higher-half kernel with page tables, physical/virtual/heap allocators
* APIC (LAPIC + IOAPIC), LAPIC timer, round-robin scheduler, `syscall`/`sysret`
* ELF64 user program loader, ring-3 execution, serial TTY (canonical mode + basic ANSI)
* Syscalls: `read`, `write`, `open`, `close`, `lseek`, `stat`, `brk`, `getpid`, `exit`/`exit_group`, and OS-specific `spawn`
* PCI enumeration (legacy I/O ports on QEMU q35), VirtIO-blk, FAT32 read-only VFS
* Userspace `shell` and `hello` (embedded in the kernel image at build time)
* [mise](https://mise.jdx.dev) tasks for build, ISO, disk, QEMU boot, and integration tests

**Next up** (see [docs/roadmap/](docs/roadmap/))

* FAT32 write/create, userspace binaries on the disk image
* VirtIO-net and a minimal TCP/IP stack

## 🚀 Goals

* x86-64 architecture
* Limine bootloader (protocol base revision 6)
* Modern 64-bit higher-half kernel
* Linux-compatible syscall interface
* Multicore threading (SMP)
* FAT32 filesystem (ext2 possible later)
* BSD-style sockets and TCP/IP networking
* Simple terminal with ANSI parsing
* GUI with basic window manager (future)
* Written in Zig for safety, simplicity, and modern tooling

## 🛠 Toolchain

* [mise](https://mise.jdx.dev) — pins Zig and defines project tasks (`mise.toml`)
* Zig (v0.16+ recommended)
* [Limine](https://github.com/Limine-Bootloader/Limine) — bootloader and ISO tooling
* `xorriso` — builds the bootable ISO
* QEMU — `qemu-system-x86_64`
* OVMF — optional, only for `mise run boot-uefi`

### macOS

Install [Homebrew](https://brew.sh) and mise, then:

```bash
brew install limine xorriso qemu
mise install
eval "$(mise activate zsh)"   # add to ~/.zshrc to persist
```

For UEFI boot testing (`mise run boot-uefi`), copy OVMF firmware into the project (one-time):

```bash
mkdir -p ovmf
cp "$(brew --prefix qemu)/share/qemu/edk2-x86_64-code.fd" ovmf/OVMF_CODE_4M.fd
dd if=/dev/zero of=ovmf/OVMF_VARS_4M.fd bs=1m count=4
```

### Linux / WSL

```bash
sudo apt install qemu-system-x86 ovmf xorriso
mise install
eval "$(mise activate bash)"   # add to ~/.bashrc to persist
```

If Limine is not available from your distro, `mise run iso` downloads the official
`limine-binary` release (v12.3.3) automatically.

For UEFI boot testing (`mise run boot-uefi`), copy OVMF firmware into the project (one-time):

```bash
mkdir -p ovmf
cp /usr/share/OVMF/OVMF_CODE_4M.fd ovmf/
cp /usr/share/OVMF/OVMF_VARS_4M.fd ovmf/
```

## 💻 Building & Running

This project uses mise tasks for build, ISO, disk, and QEMU workflows. Run `mise tasks` to list everything.

| Task | Description |
|------|-------------|
| `mise run build` | Build kernel and userspace binaries (`zig-out/bin/`) |
| `mise run iso` | Build bootable Limine ISO (`zig-out/os.iso`) |
| `mise run disk` | Create FAT32 VirtIO test disk (`zig-out/disk.img`) |
| `mise run boot` | ISO + disk + QEMU (SeaBIOS, interactive serial) |
| `mise run boot-uefi` | Same, under OVMF/UEFI |
| `mise run test` | Host-side unit tests |
| `mise run test-shell` | End-to-end smoke test (shell, `cat`, `hello`) |
| `mise run kill-qemu` | Stop a stuck QEMU instance |
| `mise run clean` | Remove `zig-out/` and `.zig-cache/` |

Quick start:

```bash
mise run boot
```

At the `os>` prompt, try `help`, `cat /README.TXT`, and `hello`.

Host unit tests (no QEMU):

```bash
mise run test
# or: zig build
```

Integration smoke test:

```bash
mise run test-shell
```

QEMU uses a VirtIO block device backed by `zig-out/disk.img`. If VFS behaves oddly after a failed disk setup, recreate the image with `mise run clean-disk` then `mise run disk`.

## 📝 Roadmap

Detailed phase docs live in [docs/roadmap/](docs/roadmap/).

| Phase | Status | Summary |
|-------|--------|---------|
| 0 — Foundation | Done | Memory map, GDT/IDT, kernel stack |
| 1 — Page tables | Done | Higher-half kernel |
| 2 — Memory | Done | Physical, virtual, and heap allocators |
| 3 — Kernel runtime | Done | APIC, timer, threads, scheduler, syscalls |
| 4 — Userspace | Done | ELF loader, TTY, shell, embedded programs |
| 5 — I/O stack | In progress | VirtIO-blk + FAT32 read done; networking next |
| 6 — SMP and GUI | Planned | Multicore, framebuffer, window manager |

**Phase 5 remaining**

* [ ] FAT32 write and file creation
* [ ] Install user programs on the FAT disk (instead of only `@embedFile`)
* [ ] VirtIO-net (or e1000) driver
* [ ] ARP, IPv4, UDP, minimal TCP
* [ ] Socket syscalls

## 🔗 Links

* Zig: [https://ziglang.org](https://ziglang.org)
* Limine: [https://github.com/Limine-Bootloader/Limine](https://github.com/Limine-Bootloader/Limine)
* OSDev.org: [https://wiki.osdev.org](https://wiki.osdev.org)
