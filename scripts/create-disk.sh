#!/bin/sh
set -e

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
disk="$root/zig-out/disk.img"

mkdir -p "$(dirname "$disk")"
dd if=/dev/zero of="$disk" bs=1M count=64 status=none 2>/dev/null

# Magic marker and MBR boot signature for virtio-blk self-test.
printf 'OSDISK01' | dd of="$disk" bs=1 seek=0 count=8 conv=notrunc status=none 2>/dev/null
printf '\x55\xaa' | dd of="$disk" bs=1 seek=510 count=2 conv=notrunc status=none 2>/dev/null
