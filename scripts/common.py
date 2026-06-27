"""Shared helpers for host-side build scripts."""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
ZIG_OUT = REPO_ROOT / "zig-out"
KERNEL_PATH = ZIG_OUT / "bin" / "kernel"
ISO_PATH = ZIG_OUT / "os.iso"
DISK_PATH = ZIG_OUT / "disk.img"
USERSPACE_BIN_DIR = ZIG_OUT / "userspace" / "bin"


def require_tool(name: str, *, install_hint: str) -> str:
    path = shutil.which(name)
    if path is None:
        print(f"error: {name} not found ({install_hint})", file=sys.stderr)
        raise SystemExit(1)
    return path
