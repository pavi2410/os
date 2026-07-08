"""In-guest TAP tests (kernel boot suite and /BIN/utest)."""

from __future__ import annotations

from pathlib import Path

import pytest

from shell_session import QemuShell
from tap_parser import extract_between, parse_tap

ROOT = Path(__file__).resolve().parents[2]

KERNEL_TAP_START = "--- TAP kernel ---"
KERNEL_TAP_END = "--- TAP kernel end ---"


@pytest.fixture(scope="module")
def repo_root() -> Path:
    iso = ROOT / "zig-out" / "os.iso"
    disk = ROOT / "zig-out" / "disk.img"
    if not iso.is_file():
        pytest.fail(f"missing {iso} (run: mise run iso)")
    if not disk.is_file():
        pytest.fail(f"missing {disk} (run: mise run disk)")
    return ROOT


@pytest.fixture(scope="module")
def kernel_boot_log(repo_root: Path) -> str:
    shell = QemuShell(repo_root)
    shell.start()
    try:
        shell.wait_ready()
        return shell.log
    finally:
        shell.close()


@pytest.fixture(scope="module")
def utest_output(repo_root: Path) -> str:
    shell = QemuShell(repo_root)
    shell.start()
    try:
        shell.wait_ready()
        return shell.run("utest")
    finally:
        shell.close()


@pytest.fixture(scope="module")
def cowtest_output(repo_root: Path) -> str:
    shell = QemuShell(repo_root)
    shell.start()
    try:
        shell.wait_ready()
        return shell.run("cowtest")
    finally:
        shell.close()


class TestKernelTap:
    def test_vfs_readme_read(self, kernel_boot_log: str) -> None:
        report = parse_tap(extract_between(kernel_boot_log, KERNEL_TAP_START, KERNEL_TAP_END))
        assert any(case.name == "vfs readme read" and case.passed for case in report.cases)

    def test_udp_dns_reply(self, kernel_boot_log: str) -> None:
        report = parse_tap(extract_between(kernel_boot_log, KERNEL_TAP_START, KERNEL_TAP_END))
        assert any(case.name == "udp dns reply" and case.passed for case in report.cases)

    def test_physical_pages_free(self, kernel_boot_log: str) -> None:
        report = parse_tap(extract_between(kernel_boot_log, KERNEL_TAP_START, KERNEL_TAP_END))
        assert any(case.name == "physical pages free" and case.passed for case in report.cases)

    def test_kernel_plan(self, kernel_boot_log: str) -> None:
        report = parse_tap(extract_between(kernel_boot_log, KERNEL_TAP_START, KERNEL_TAP_END))
        report.assert_all_passed("kernel TAP")


class TestUtestTap:
    def test_bytes_big_endian_helpers(self, utest_output: str) -> None:
        report = parse_tap(utest_output)
        assert any(case.name == "bytes big endian helpers" and case.passed for case in report.cases)

    def test_bytes_little_endian_helpers(self, utest_output: str) -> None:
        report = parse_tap(utest_output)
        assert any(case.name == "bytes little endian helpers" and case.passed for case in report.cases)

    def test_dns_build_query(self, utest_output: str) -> None:
        report = parse_tap(utest_output)
        assert any(case.name == "dns buildQuery example.com" and case.passed for case in report.cases)

    def test_dns_encode_name_rejects(self, utest_output: str) -> None:
        report = parse_tap(utest_output)
        assert any(case.name == "dns encodeName rejects bad names" and case.passed for case in report.cases)

    def test_dns_parse_first_a(self, utest_output: str) -> None:
        report = parse_tap(utest_output)
        assert any(case.name == "dns parseFirstA" and case.passed for case in report.cases)

    def test_utest_plan(self, utest_output: str) -> None:
        report = parse_tap(utest_output)
        report.assert_all_passed("utest TAP")


class TestCowtestTap:
    def test_child_write_parent_unchanged(self, cowtest_output: str) -> None:
        report = parse_tap(cowtest_output)
        assert any(case.name == "child write parent unchanged" and case.passed for case in report.cases)

    def test_both_sides_write(self, cowtest_output: str) -> None:
        report = parse_tap(cowtest_output)
        assert any(case.name == "both sides write" and case.passed for case in report.cases)

    def test_cowtest_plan(self, cowtest_output: str) -> None:
        report = parse_tap(cowtest_output)
        report.assert_all_passed("cowtest TAP")
