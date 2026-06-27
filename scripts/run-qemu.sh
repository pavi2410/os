#!/bin/sh
# Boot the OS in QEMU. Requires zig-out/os.iso and zig-out/disk.img.
# Usage: run-qemu.sh [--uefi] [extra qemu args...]
set -e

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$root"

mode=bios
while [ $# -gt 0 ]; do
    case "$1" in
        --uefi)
            mode=uefi
            shift
            ;;
        *)
            break
            ;;
    esac
done

iso="$root/zig-out/os.iso"
disk="$root/zig-out/disk.img"

if [ ! -f "$iso" ]; then
    echo "error: $iso not found (run: mise run iso)" >&2
    exit 1
fi
if [ ! -f "$disk" ]; then
    echo "error: $disk not found (run: mise run disk)" >&2
    exit 1
fi

set -- qemu-system-x86_64 -M q35

if [ "$mode" = uefi ]; then
    code="$root/ovmf/OVMF_CODE_4M.fd"
    vars="$root/ovmf/OVMF_VARS_4M.fd"
    if [ ! -f "$code" ] || [ ! -f "$vars" ]; then
        echo "error: OVMF firmware missing in ovmf/ (see README)" >&2
        exit 1
    fi
    set -- "$@" \
        -drive "if=pflash,format=raw,readonly=on,file=$code" \
        -drive "if=pflash,format=raw,file=$vars"
fi

set -- "$@" \
    -cdrom "$iso" \
    -boot d \
    -drive "file=$disk,if=none,format=raw,id=disk0" \
    -device virtio-blk-pci,drive=disk0,disable-legacy=on \
    -serial stdio \
    -no-reboot \
    "$@"

exec "$@"
