#!/bin/sh
# Boot the OS and drive the serial shell with a fixed script, then verify the
# expected output. Self-terminating: backgrounds QEMU and kills it after the
# scripted input has been consumed (macOS has no `timeout`).
set -e

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$root"

# Expects zig-out/os.iso and zig-out/disk.img (mise run test-shell runs iso + disk first).
out="/tmp/os-shell-test.log"
rm -f "$out"

{
    sleep 7
    printf 'help\r'
    sleep 1
    printf 'cat /README.TXT\r'
    sleep 1
    printf 'hello\r'
    sleep 2
    printf 'pid\r'
    sleep 1
    printf 'hello\r'
    sleep 2
    printf 'exit\r'
    sleep 2
} | qemu-system-x86_64 \
    -M q35 \
    -cdrom zig-out/os.iso \
    -boot d \
    -drive file=zig-out/disk.img,if=none,format=raw,id=disk0 \
    -device virtio-blk-pci,drive=disk0,disable-legacy=on \
    -serial stdio \
    -display none \
    -no-reboot \
    >"$out" 2>&1 &

qpid=$!
sleep 18
kill "$qpid" 2>/dev/null || true
pkill -f "qemu-system-x86_64.*os.iso" 2>/dev/null || true

echo "=== serial log (tail) ==="
tail -25 "$out"

echo ""
echo "=== checks ==="
fail=0
for needle in \
    "Simple shell ready" \
    "Built-ins: help, exit, pid, cat" \
    "Programs: hello" \
    "Hello from FAT on virtio-blk" \
    "Hello from userspace!"
do
    if grep -q "$needle" "$out"; then
        echo "ok: $needle"
    else
        echo "MISSING: $needle"
        fail=1
    fi
done

if grep -q "Fault" "$out"; then
    echo "FAULT detected in serial log"
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo "shell test FAILED"
    exit 1
fi

echo "shell test PASSED"
