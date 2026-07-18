"""SMP smoke tests: boot with -smp N and check online CPU count."""

from __future__ import annotations

from pathlib import Path

import pytest

from shell_session import QemuShell, assert_contains

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="module")
def repo_root() -> Path:
    iso = ROOT / "zig-out" / "os.iso"
    disk = ROOT / "zig-out" / "disk.img"
    if not iso.is_file():
        pytest.fail(f"missing {iso} (run: mise run iso)")
    if not disk.is_file():
        pytest.fail(f"missing {disk} (run: mise run disk)")
    return ROOT


@pytest.mark.parametrize("smp", [2, 4])
def test_smp_cpus_online(repo_root: Path, smp: int) -> None:
    shell = QemuShell(repo_root, extra=("-smp", str(smp)))
    shell.start()
    try:
        shell.wait_ready()
        assert_contains(shell.log, f"CPUs available: {smp}", f"smp{smp} available")
        assert_contains(shell.log, f"CPUs online: {smp}", f"smp{smp} online")
        # Kernel workers are IPI'd onto each AP.
        for cpu in range(1, smp):
            assert_contains(shell.log, f"cpu {cpu} worker running", f"smp{smp} worker cpu{cpu}")
        window = shell.run("echo hello-smp")
        assert_contains(window, "hello-smp", f"smp{smp} echo")
        shell.assert_no_faults()
    finally:
        shell.close()
