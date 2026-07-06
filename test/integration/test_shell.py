"""Serial shell integration tests (prompt-synced, one QEMU session per phase)."""

from __future__ import annotations

import socket
import subprocess
import sys
import time
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


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_for_port(port: int) -> None:
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise TimeoutError(f"server did not listen on port {port}")


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
        run_case(shell, "ls -l /BIN", "HELLO", case="ls -l /BIN")
        run_case(shell, "ls /BIN", "DIG", case="ls /BIN dig")
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
        run_case(shell, "dig example.com", "ANSWER SECTION", case="dig example.com")
        run_case(shell, "dig example.com", "IN  A", case="dig A record")
        run_case(shell, "ping", "ping: 10.0.2.2 reply", case="ping gateway")
        run_case(
            shell,
            "ping 104.20.23.154",
            "ping: 104.20.23.154 reply",
            case="ping off-subnet",
        )
        run_case(shell, "ip addr", "10.0.2.15/24", case="ip addr")
        run_case(shell, "ip route", "default via 10.0.2.2", case="ip route")
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


def test_tcp_curl_from_host(repo_root: Path, tmp_path: Path) -> None:
    (tmp_path / "index.html").write_text("hello from host tcp\n", encoding="utf-8")
    port = free_port()
    server = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "http.server",
            str(port),
            "--bind",
            "127.0.0.1",
            "--directory",
            str(tmp_path),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_port(port)
        shell = QemuShell(repo_root)
        shell.start()
        try:
            shell.wait_ready()
            run_case(
                shell,
                f"curl 10.0.2.2 {port}",
                "hello from host tcp",
                case="curl host tcp",
            )
            shell.assert_no_faults()
        finally:
            shell.close()
    finally:
        server.terminate()
        server.wait(timeout=5)
