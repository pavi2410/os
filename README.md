# os

**A hobby operating system** in Zig, targeting x86-64 with [Limine](https://github.com/Limine-Bootloader/Limine), aiming for Linux ABI compatibility, multicore support, filesystems, networking, and eventually a GUI.

## 🚀 Goals

* x86-64 architecture
* Limine bootloader (protocol base revision 6)
* Modern 64-bit higher-half kernel
* Linux-compatible syscall interface
* Multicore threading (SMP)
* ext2 or FAT32 filesystem
* BSD-style sockets and TCP/IP networking
* Simple terminal with ANSI parsing
* GUI with basic window manager (future)
* Written in Zig for safety, simplicity, and modern tooling

## 🛠 Toolchain

* Zig (v0.16+ recommended)
* [Limine](https://github.com/Limine-Bootloader/Limine) — bootloader and ISO tooling
* `xorriso` — builds the bootable ISO
* QEMU — `qemu-system-x86_64`
* OVMF — optional, only for `mise run run-uefi`

### macOS

Install [Homebrew](https://brew.sh) and [mise](https://mise.jdx.dev), then:

```bash
brew install limine xorriso qemu
mise install
eval "$(mise activate zsh)"   # add to ~/.zshrc to persist
```

For UEFI boot testing (`mise run run-uefi`), copy OVMF firmware into the project (one-time):

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

For UEFI boot testing (`mise run run-uefi`), copy OVMF firmware into the project (one-time):

```bash
mkdir -p ovmf
cp /usr/share/OVMF/OVMF_CODE_4M.fd ovmf/
cp /usr/share/OVMF/OVMF_VARS_4M.fd ovmf/
```

## 💻 Building & Running

This project uses [mise](https://mise.jdx.dev) tasks for build, ISO, disk, and QEMU workflows.
Run `mise tasks` to list everything.

Build the kernel:

```bash
mise run build
# or: zig build
```

Build a bootable ISO (uses Homebrew Limine when installed, otherwise downloads it):

```bash
mise run iso
```

Create the FAT32 test disk and run in QEMU (SeaBIOS, default):

```bash
mise run run
```

Run under OVMF/UEFI instead (requires OVMF firmware in `ovmf/`):

```bash
mise run run-uefi
```

Run host unit tests:

```bash
mise run test
# or: zig build test
```

Integration smoke test (serial shell + virtio disk):

```bash
mise run test-shell
```

## 📝 Roadmap

* [x] Hello kernel in Zig
* [ ] Page tables and higher-half kernel
* [ ] Memory allocator (physical/virtual)
* [ ] ELF loader for user programs
* [ ] Initial Linux-compatible syscalls
* [ ] Filesystem driver (ext2 or FAT32)
* [ ] Network driver (virtio-net or e1000)
* [ ] Simple TCP/IP stack
* [ ] Terminal + TTY driver
* [ ] Shell + user programs
* [ ] SMP multicore support
* [ ] GUI with framebuffer / window manager

## 🔗 Links

* Zig: [https://ziglang.org](https://ziglang.org)
* Limine: [https://github.com/Limine-Bootloader/Limine](https://github.com/Limine-Bootloader/Limine)
* OSDev.org: [https://wiki.osdev.org](https://wiki.osdev.org)
