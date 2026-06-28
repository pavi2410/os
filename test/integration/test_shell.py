"""Serial shell integration tests (prompt-synced, one QEMU session per phase)."""

from __future__ import annotations

from pathlib import Path

import pytest

from shell_session import QemuShell, assert_cat_exact, assert_contains, sync_disk

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def repo_root() -> Path:
    iso = ROOT / "zig-out" / "os.iso"
    disk = ROOT / "zig-out" / "disk.img"
    if not iso.is_file():
        pytest.fail(f"missing {iso} (run: mise run iso)")
    if not disk.is_file():
        pytest.fail(f"missing {disk} (run: mise run disk)")
    return ROOT


def run_case(shell: QemuShell, cmd: str, *needles: str, case: str | None = None) -> str:
    label = case or cmd
    window = shell.run(cmd)
    for needle in needles:
        assert_contains(window, needle, label)
    return window


def test_shell_smoke_and_persistence(repo_root: Path) -> None:
    shell = QemuShell(repo_root)
    shell.start()
    try:
        shell.wait_ready()
        assert_contains(shell.log, QemuShell.READY, "boot")

        run_case(
            shell,
            "help",
            "Built-ins: help, exit, pid, echo, cat, ls, write, rm, mkdir, rmdir, cd, pwd, date",
            case="help",
        )
        run_case(shell, "pwd", "/", case="pwd root")
        date_out = run_case(shell, "date", case="date")
        if "-" not in date_out or ":" not in date_out or "UTC" not in date_out:
            raise AssertionError(f"date: unexpected output:\n{date_out}")
        run_case(shell, "echo hello from echo", "hello from echo", case="echo")
        run_case(
            shell,
            "cat /README.TXT",
            "Hello from FAT on virtio-blk",
            case="cat readme",
        )
        run_case(shell, "ls", "README.TXT", case="ls root")
        run_case(shell, "ls /BIN", "HELLO", case="ls /BIN")
        mkdir_out = shell.run("mkdir /TDIR")
        if "mkdir: ok" not in mkdir_out and "mkdir: failed" not in mkdir_out:
            raise AssertionError(f"mkdir: unexpected output:\n{mkdir_out}")
        run_case(shell, "cd /TDIR", case="cd tdir")
        run_case(shell, "pwd", "/TDIR", case="pwd tdir")
        run_case(shell, "write NOTE.TXT nested", "write: ok", case="write relative")
        run_case(shell, "cat NOTE.TXT", "nested", case="cat relative")
        run_case(shell, "cd ..", case="cd parent")
        run_case(shell, "pwd", "/", case="pwd after cd ..")
        run_case(shell, "cat /TDIR/NOTE.TXT", "nested", case="cat in dir")
        run_case(shell, "rm /TDIR/NOTE.TXT", "rm: ok", case="rm note in dir")
        run_case(shell, "rmdir /TDIR", "rmdir: ok", case="rmdir tdir")
        run_case(shell, "ls -l /BIN", "4880 HELLO", case="ls -l /BIN")
        run_case(shell, "write /yo.txt yoman", "write: ok", case="write yo")
        run_case(shell, "cat /YO.TXT", "yoman", case="cat yo")
        run_case(
            shell,
            "write /TEST.TXT persisted on disk!",
            "write: ok",
            case="write persist",
        )
        append_path = "/SMKAPP.TXT"
        run_case(shell, f"write {append_path} first", "write: ok", case="append truncate")
        run_case(shell, f"write -a {append_path} second", "write: ok", case="append 2")
        append_out = run_case(shell, f"cat {append_path}", case="cat append")
        assert_cat_exact(append_out, append_path, "firstsecond", "cat append")
        run_case(shell, f"rm {append_path}", "rm: ok", case="rm append")
        run_case(shell, f"cat {append_path}", "cat: open failed", case="cat removed")
        run_case(
            shell,
            "cat /TEST.TXT",
            "persisted on disk!",
            case="cat persist",
        )
        run_case(shell, "hello", "Hello from userspace!", case="fork/exec hello")
        pid_out = run_case(shell, "pid", case="pid")
        assert any(ch.isdigit() for ch in pid_out), f"pid: no digits in:\n{pid_out}"
        shell.assert_no_faults()
    finally:
        shell.close()

    sync_disk(repo_root)

    shell2 = QemuShell(repo_root)
    shell2.start()
    try:
        shell2.wait_ready()
        run_case(shell2, "cat /YO.TXT", "yoman", case="persist cat yo")
        run_case(
            shell2,
            "cat /TEST.TXT",
            "persisted on disk!",
            case="persist cat test",
        )
        shell2.assert_no_faults()
    finally:
        shell2.close()
