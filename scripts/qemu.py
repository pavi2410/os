#!/usr/bin/env python3
"""Launch this project's QEMU machine with a QMP control socket."""

from __future__ import annotations

import argparse
import logging
import os
import subprocess
from collections.abc import Sequence
from pathlib import Path

from qemu.qmp.legacy import QEMUMonitorProtocol

from scripts.common import DISK_PATH, ISO_PATH, REPO_ROOT, require_tool

QMP_SOCKET = REPO_ROOT / "zig-out" / "qemu.qmp.sock"
QEMU_CONFIG = REPO_ROOT / "config" / "qemu.ini"
QEMU_UEFI_CONFIG = REPO_ROOT / "config" / "qemu-uefi.ini"
OVMF_CODE = REPO_ROOT / "ovmf" / "OVMF_CODE_4M.fd"
OVMF_VARS = REPO_ROOT / "ovmf" / "OVMF_VARS_4M.fd"

logger = logging.getLogger(__name__)


def prepare_qmp_socket() -> None:
    if QMP_SOCKET.exists():
        QMP_SOCKET.unlink()


def validate_boot_files(*, uefi: bool) -> None:
    if not ISO_PATH.is_file():
        logger.error("%s not found (run: mise run iso)", ISO_PATH)
        raise SystemExit(1)
    if not DISK_PATH.is_file():
        logger.error("%s not found (run: mise run disk)", DISK_PATH)
        raise SystemExit(1)
    if uefi and (not OVMF_CODE.is_file() or not OVMF_VARS.is_file()):
        logger.error("OVMF firmware missing in ovmf/ (see README)")
        raise SystemExit(1)


def build_qemu_argv(
    *,
    uefi: bool = False,
    display_none: bool = False,
    extra: Sequence[str] = (),
) -> list[str]:
    validate_boot_files(uefi=uefi)
    qemu = require_tool("qemu-system-x86_64", install_hint="macOS: brew install qemu")

    argv = [
        qemu,
        "-readconfig",
        str(QEMU_CONFIG),
    ]
    if uefi:
        argv.extend(["-readconfig", str(QEMU_UEFI_CONFIG)])
    if display_none:
        argv.extend(["-display", "none"])
    # mon:stdio traps host SIGINT (e.g. pty ^C) and forwards it to the guest
    # serial instead of killing QEMU — required for Ctrl-C integration tests.
    argv.extend(["-serial", "mon:stdio", "-no-reboot"])
    argv.extend(extra)
    return argv


def qmp_quit(socket_path: Path = QMP_SOCKET) -> bool:
    if not socket_path.exists():
        return False

    try:
        monitor = QEMUMonitorProtocol(str(socket_path))
        monitor.connect()
        monitor.cmd("quit")
        monitor.close()
        return True
    except Exception:
        logger.debug("QMP quit failed for %s", socket_path, exc_info=True)
        return False


def stop_qemu() -> None:
    if qmp_quit():
        return

    subprocess.run(
        ["pkill", "-f", "qemu-system-x86_64.*os.iso"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    parser = argparse.ArgumentParser(description="Boot the OS in QEMU")
    parser.add_argument("--uefi", action="store_true", help="boot with OVMF/UEFI firmware")
    parser.add_argument(
        "extra",
        nargs=argparse.REMAINDER,
        help="extra arguments passed to qemu-system-x86_64",
    )
    args = parser.parse_args()
    extra = args.extra
    if extra and extra[0] == "--":
        extra = extra[1:]

    os.chdir(REPO_ROOT)
    prepare_qmp_socket()
    argv = build_qemu_argv(uefi=args.uefi, extra=extra)
    os.execvp(argv[0], argv)


if __name__ == "__main__":
    main()
