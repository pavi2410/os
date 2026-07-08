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


@pytest.fixture(scope="module")
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


@pytest.fixture(scope="module")
def shell_session(repo_root: Path) -> QemuShell:
    shell = QemuShell(repo_root)
    shell.start()
    shell.wait_ready()
    yield shell
    shell.close()


class TestShellBoot:
    def test_boot_ready(self, shell_session: QemuShell) -> None:
        assert_contains(shell_session.log, QemuShell.READY, "boot")


class TestShellBuiltins:
    def test_help(self, shell_session: QemuShell) -> None:
        run_case(
            shell_session,
            "help",
            "Built-ins: help, exit, pid, echo, cat, ls, write, rm, mkdir, rmdir, cd, pwd, date, export",
            case="help",
        )

    def test_pwd_root(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "pwd", "/", case="pwd root")

    def test_date(self, shell_session: QemuShell) -> None:
        date_out = run_case(shell_session, "date", case="date")
        if "-" not in date_out or ":" not in date_out or "UTC" not in date_out:
            raise AssertionError(f"date: unexpected output:\n{date_out}")

    def test_echo(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "echo hello from echo", "hello from echo", case="echo")

    def test_echo_variable(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "echo $PATH", "/BIN", case="echo PATH")
        run_case(shell_session, "export FOO=bar", case="export foo for echo")
        run_case(shell_session, "echo $FOO", "bar", case="echo FOO")

    def test_cat_readme(self, shell_session: QemuShell) -> None:
        run_case(
            shell_session,
            "cat /README.TXT",
            "Hello from FAT on virtio-blk",
            case="cat readme",
        )

    def test_ls_root(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "ls", "README.TXT", case="ls root")

    def test_ls_bin(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "ls /BIN", "SHELL", case="ls /BIN")

    def test_pid(self, shell_session: QemuShell) -> None:
        pid_out = run_case(shell_session, "pid", case="pid")
        assert any(ch.isdigit() for ch in pid_out), f"pid: no digits in:\n{pid_out}"


class TestShellFilesystem:
    def test_mkdir_cd_write_cat(self, shell_session: QemuShell) -> None:
        mkdir_out = shell_session.run("mkdir /TDIR")
        if "mkdir: ok" not in mkdir_out and "mkdir: failed" not in mkdir_out:
            raise AssertionError(f"mkdir: unexpected output:\n{mkdir_out}")
        run_case(shell_session, "cd /TDIR", case="cd tdir")
        run_case(shell_session, "pwd", "/TDIR", case="pwd tdir")
        run_case(shell_session, "write NOTE.TXT nested", "write: ok", case="write relative")
        run_case(shell_session, "cat NOTE.TXT", "nested", case="cat relative")
        run_case(shell_session, "cd ..", case="cd parent")
        run_case(shell_session, "pwd", "/", case="pwd after cd ..")
        run_case(shell_session, "cat /TDIR/NOTE.TXT", "nested", case="cat in dir")

    def test_rm_rmdir(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "rm /TDIR/NOTE.TXT", "rm: ok", case="rm note in dir")
        run_case(shell_session, "rmdir /TDIR", "rmdir: ok", case="rmdir tdir")

    def test_ls_long_bin(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "ls -l /BIN", "SHELL", case="ls -l /BIN")
        run_case(shell_session, "ls /BIN", "DIG", case="ls /BIN dig")

    def test_write_and_cat(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "write /yo.txt yoman", "write: ok", case="write yo")
        run_case(shell_session, "cat /YO.TXT", "yoman", case="cat yo")
        run_case(
            shell_session,
            "write /TEST.TXT persisted on disk!",
            "write: ok",
            case="write persist",
        )

    def test_append(self, shell_session: QemuShell) -> None:
        append_path = "/SMKAPP.TXT"
        run_case(shell_session, f"write {append_path} first", "write: ok", case="append truncate")
        run_case(shell_session, f"write -a {append_path} second", "write: ok", case="append 2")
        append_out = run_case(shell_session, f"cat {append_path}", case="cat append")
        assert_cat_exact(append_out, append_path, "firstsecond", "cat append")
        run_case(shell_session, f"rm {append_path}", "rm: ok", case="rm append")
        run_case(shell_session, f"cat {append_path}", "cat: open failed", case="cat removed")
        run_case(
            shell_session,
            "cat /TEST.TXT",
            "persisted on disk!",
            case="cat persist",
        )


class TestShellEnvironment:
    def test_export_envtest(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "export FOO=bar", case="export foo")
        run_case(shell_session, "envtest", "bar", case="envtest reads FOO")

    def test_path_lookup(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "lscpu", "Architecture:", case="PATH resolves lscpu")

    def test_ls_home_expansion(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "ls $HOME", "README.TXT", case="ls HOME")
        run_case(shell_session, "ls $HOME/BIN", "SHELL", case="ls HOME/BIN")

    def test_unset(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "export FOO=bar", case="export foo for unset")
        run_case(shell_session, "envtest", "bar", case="envtest before unset")
        run_case(shell_session, "unset FOO", case="unset foo")
        run_case(shell_session, "envtest", "(unset)", case="envtest after unset")

    def test_prefix_env(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "FOO=qux envtest", "qux", case="prefix env envtest")
        run_case(shell_session, "envtest", "(unset)", case="prefix env not persisted")
        run_case(shell_session, "FOO=bar echo $FOO", "bar", case="prefix env echo")


class TestShellOperators:
    def test_and_short_circuit(self, shell_session: QemuShell) -> None:
        window = shell_session.run("false && echo no")
        if "\nno\n" in window or window.rstrip().endswith("no"):
            raise AssertionError(f"&& short-circuit failed:\n{window}")

    def test_or_fallback(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "false || echo yes", "yes", case="or runs on failure")

    def test_and_before_or(self, shell_session: QemuShell) -> None:
        window = shell_session.run("true && echo a || echo b")
        assert_contains(window, "a", "and then or")
        if "b" in window.split("true && echo a || echo b", 1)[-1]:
            raise AssertionError(f"unexpected b in:\n{window}")

    def test_semicolon_with_and(self, shell_session: QemuShell) -> None:
        window = shell_session.run("false; false && echo x")
        if "x" in window.split("false; false && echo x", 1)[-1]:
            raise AssertionError(f"unexpected x in:\n{window}")


class TestShellSemicolon:
    def test_semicolon_runs_last_status(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "false; echo ok", "ok", case="semicolon second command")
        run_case(shell_session, "echo $?", "0", case="semicolon last status")


class TestShellQuotes:
    def test_double_quoted_argument(self, shell_session: QemuShell) -> None:
        run_case(shell_session, 'echo "hello world"', "hello world", case="quoted echo")


class TestShellComments:
    def test_hash_comment(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "echo hello # goodbye", "hello", case="hash comment")


class TestShellExitStatus:
    def test_exit_status_after_failure(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "cat /NOPE", "cat: open failed", case="cat missing file")
        run_case(shell_session, "echo $?", "1", case="echo exit status")

    def test_exit_status_after_success(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "echo ok", "ok", case="echo success")
        run_case(shell_session, "echo $?", "0", case="echo zero status")

    def test_true_false_status(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "false", case="false builtin")
        run_case(shell_session, "echo $?", "1", case="false status")
        run_case(shell_session, "true", case="true builtin")
        run_case(shell_session, "echo $?", "0", case="true status")


class TestShellDevfs:
    def test_devtest(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "devtest", "devtest: ok", case="devnull and devzero")


class TestShellPrograms:
    def test_lscpu(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "lscpu", "Architecture:", case="fork/exec lscpu")

    def test_dig(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "dig example.com", "ANSWER SECTION", case="dig example.com")
        run_case(shell_session, "dig example.com", "IN  A", case="dig A record")

    def test_ping_gateway(self, shell_session: QemuShell) -> None:
        ping_out = run_case(
            shell_session,
            "ping -c 2",
            "ping: 10.0.2.2 reply seq=1",
            case="ping gateway",
        )
        assert_contains(ping_out, "2 packets transmitted, 2 received, 0% packet loss", "ping stats")
        assert_contains(ping_out, "rtt min/avg/max", "ping rtt stats")

    def test_ping_off_subnet(self, shell_session: QemuShell) -> None:
        run_case(
            shell_session,
            "ping -c 2 104.20.23.154",
            "ping: 104.20.23.154 reply seq=1",
            case="ping off-subnet",
        )

    def test_ip(self, shell_session: QemuShell) -> None:
        run_case(shell_session, "ip addr", "10.0.2.15/24", case="ip addr")
        run_case(shell_session, "ip route", "default via 10.0.2.2", case="ip route")

    def test_no_faults(self, shell_session: QemuShell) -> None:
        shell_session.assert_no_faults()


@pytest.fixture(scope="module")
def persisted_disk(repo_root: Path, shell_session: QemuShell) -> Path:
    shell_session.assert_no_faults()
    sync_disk(repo_root)
    return repo_root


@pytest.fixture(scope="module")
def rebooted_shell(persisted_disk: Path) -> QemuShell:
    shell = QemuShell(persisted_disk)
    shell.start()
    shell.wait_ready()
    yield shell
    shell.close()


class TestShellPersistence:
    def test_persist_cat_yo(self, rebooted_shell: QemuShell) -> None:
        run_case(rebooted_shell, "cat /YO.TXT", "yoman", case="persist cat yo")

    def test_persist_cat_test(self, rebooted_shell: QemuShell) -> None:
        run_case(
            rebooted_shell,
            "cat /TEST.TXT",
            "persisted on disk!",
            case="persist cat test",
        )

    def test_no_faults_after_reboot(self, rebooted_shell: QemuShell) -> None:
        rebooted_shell.assert_no_faults()


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
