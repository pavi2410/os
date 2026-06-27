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
    printf 'echo hello from echo\r'
    sleep 1
    printf 'cat /README.TXT\r'
    sleep 1
    printf 'ls\r'
    sleep 1
    printf 'ls /BIN\r'
    sleep 1
    printf 'ls -l /BIN\r'
    sleep 1
    printf 'write /TEST.TXT persisted on disk!\r'
    sleep 1
    printf 'cat /TEST.TXT\r'
    sleep 1
    printf 'hello\r'
    sleep 2
    printf 'pid\r'
    sleep 1
    printf 'hello\r'
    sleep 2
    printf 'exit\r'
    sleep 2
} | sh scripts/run-qemu.sh -display none >"$out" 2>&1 &

qpid=$!
    sleep 25
kill "$qpid" 2>/dev/null || true
pkill -f "qemu-system-x86_64.*os.iso" 2>/dev/null || true

echo "=== serial log (tail) ==="
tail -25 "$out"

echo ""
echo "=== checks ==="
fail=0
for needle in \
    "Simple shell ready" \
    "Built-ins: help, exit, pid, echo, cat, ls, write" \
    "hello from echo" \
    "Programs in /BIN: hello" \
    "README.TXT" \
    "HELLO" \
    "4880 HELLO" \
    "persisted on disk!" \
    "Hello from FAT on virtio-blk" \
    "Hello from userspace!"
do
    if grep -qF -- "$needle" "$out"; then
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
