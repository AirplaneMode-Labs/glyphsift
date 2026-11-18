#!/usr/bin/env python3
"""Tests for the wheel-tag check in tests/python/check_wheel.py. Run with -I:

    python3 -I tests/python/test_check_wheel.py          (run by tests/scripts/check-wheel-tags.sh, so by run-all.sh)

Why this file exists. CI run 44325740893 failed only on `wheel and sdist (ubuntu-latest)`: a manylinux wheel's
FILENAME carries a compressed tag set (PEP 425), `cp39-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64`, and its
WHEEL file lists one `Tag:` line per expanded tag (`Tag: cp39-abi3-manylinux2014_x86_64`, `Tag: cp39-abi3-
manylinux_2_17_x86_64`). The old check looked for the literal string `Tag: cp39-abi3-<compressed name>` in WHEEL,
which maturin never writes, so it failed on Linux only; macOS and Windows tags have no dot, so they passed. The
Mac that develops this repository has no Linux wheel, so the cases below build synthetic wheels (a zip with a
WHEEL file and the filename under test) and run the real script on them.

Two layers:
  - TagCheckEndToEnd runs `python -I check_wheel.py <wheel> <version>` on synthetic wheels and reads the one
    output line about the tag check. It works against the old script too (the red log).
  - TagFunctions tests expand_tags / wheel_file_tags / tag_mismatch directly (they do not exist in the old script).

The WHEEL texts below are the real ones: the manylinux text is verbatim from the Linux wheel CI built in run
43667702791 (maturin 1.16.0), the macOS and win_amd64 texts from the wheels of run 44325740893.

CHECK_WHEEL_SCRIPT overrides the script under test (an absolute file path). It exists so the suite can be run
against the pre-fix script for the red log; leave it unset otherwise.
"""
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.environ.get("CHECK_WHEEL_SCRIPT") or os.path.join(HERE, "check_wheel.py")
VERSION = "0.1.1"
LABEL = "WHEEL records the same"  # the stable start of the check's label in both the old and the new script

WHEEL_HEAD = "Wheel-Version: 1.0\nGenerator: maturin (1.16.0)\nRoot-Is-Purelib: false\n"


def wheel_text(*tags, head=WHEEL_HEAD):
    return head + "".join(f"Tag: {t}\n" for t in tags)


MANYLINUX_NAME = f"glyphsift-{VERSION}-cp39-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64.whl"
MANYLINUX_WHEEL = wheel_text("cp39-abi3-manylinux2014_x86_64", "cp39-abi3-manylinux_2_17_x86_64")
MACOS_NAME = f"glyphsift-{VERSION}-cp39-abi3-macosx_11_0_arm64.whl"
MACOS_WHEEL = wheel_text("cp39-abi3-macosx_11_0_arm64")
WIN_NAME = f"glyphsift-{VERSION}-cp39-abi3-win_amd64.whl"
WIN_WHEEL = wheel_text("cp39-abi3-win_amd64")


def load_module():
    spec = importlib.util.spec_from_file_location("check_wheel_under_test", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TagCheckEndToEnd(unittest.TestCase):
    """The real script, run as CI runs it, on a synthetic wheel. Only the tag line is judged: the other checks
    fail on these stripped wheels (no stub, no licence) and that is expected."""

    def run_check(self, filename, wheel_file_text):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, filename)
            di = f"glyphsift-{VERSION}.dist-info/"
            with zipfile.ZipFile(path, "w") as z:
                z.writestr(di + "WHEEL", wheel_file_text)
                z.writestr(di + "METADATA", "Metadata-Version: 2.4\nName: glyphsift\n")
            p = subprocess.run([sys.executable, "-I", SCRIPT, path, VERSION], capture_output=True, text=True, timeout=60)
        self.assertNotIn("Traceback", p.stderr, p.stderr)
        self.assertIn(p.returncode, (0, 1), f"exit {p.returncode}: {p.stderr}")
        lines = [ln for ln in p.stdout.splitlines() if LABEL in ln]
        self.assertEqual(len(lines), 1, f"want exactly one tag-check line, got {lines!r}\n{p.stdout}")
        return lines[0][:5].strip(), p.stdout

    def assertTagOk(self, filename, text):
        status, out = self.run_check(filename, text)
        self.assertEqual(status, "ok", out)

    def assertTagFails(self, filename, text):
        status, out = self.run_check(filename, text)
        self.assertEqual(status, "FAIL", out)

    # --- the three platforms CI builds -------------------------------------------------------------------
    def test_macos_wheel_passes(self):
        self.assertTagOk(MACOS_NAME, MACOS_WHEEL)

    def test_win_amd64_wheel_passes(self):
        self.assertTagOk(WIN_NAME, WIN_WHEEL)

    def test_compressed_manylinux_name_passes(self):
        # The CI fault: red against the old script, green against the fixed one.
        self.assertTagOk(MANYLINUX_NAME, MANYLINUX_WHEEL)

    def test_tag_line_order_does_not_matter(self):
        self.assertTagOk(MANYLINUX_NAME, wheel_text("cp39-abi3-manylinux_2_17_x86_64", "cp39-abi3-manylinux2014_x86_64"))

    def test_crlf_wheel_file_passes(self):
        self.assertTagOk(MANYLINUX_NAME, MANYLINUX_WHEEL.replace("\n", "\r\n"))

    # --- the check stays strict: none of these may pass --------------------------------------------------
    def test_compressed_name_with_only_one_tag_listed_fails(self):
        self.assertTagFails(MANYLINUX_NAME, wheel_text("cp39-abi3-manylinux_2_17_x86_64"))

    def test_extra_tag_in_wheel_file_fails(self):
        self.assertTagFails(MACOS_NAME, wheel_text("cp39-abi3-macosx_11_0_arm64", "cp39-abi3-macosx_10_12_x86_64"))

    def test_other_platform_fails(self):
        self.assertTagFails(MACOS_NAME, wheel_text("cp39-abi3-macosx_11_0_x86_64"))

    def test_other_python_or_abi_fails(self):
        self.assertTagFails(WIN_NAME, wheel_text("cp311-cp311-win_amd64"))

    def test_no_tag_lines_fails(self):
        self.assertTagFails(WIN_NAME, WHEEL_HEAD)

    def test_unparseable_tag_line_fails_without_a_traceback(self):
        self.assertTagFails(WIN_NAME, wheel_text("win_amd64"))

    def test_not_a_substring_match_longer_platform(self):
        # The old check was `"Tag: cp39-abi3-win_amd64" in WHEEL`: a longer tag that starts the same way passed.
        self.assertTagFails(WIN_NAME, wheel_text("cp39-abi3-win_amd64_debug"))

    def test_not_a_substring_match_other_header(self):
        # ... and so did the same text inside another header (`X-Tag:` contains `Tag:`), with no Tag line at all.
        self.assertTagFails(WIN_NAME, WHEEL_HEAD + "X-Tag: cp39-abi3-win_amd64\n")

    def test_not_a_substring_match_comment_in_value(self):
        self.assertTagFails(WIN_NAME, WHEEL_HEAD + "Generator: maturin Tag: cp39-abi3-win_amd64\n")

    def test_filename_that_does_not_parse_fails_without_a_traceback(self):
        self.assertTagFails(f"glyphsift-{VERSION}-py3-none-any.whl", wheel_text("py3-none-any"))


class TagFunctions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m = load_module()

    def test_expand_single_tag(self):
        self.assertEqual(self.m.expand_tags("cp39-abi3-win_amd64"), frozenset({"cp39-abi3-win_amd64"}))

    def test_expand_compressed_platform(self):
        self.assertEqual(
            self.m.expand_tags("cp39-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64"),
            frozenset({"cp39-abi3-manylinux2014_x86_64", "cp39-abi3-manylinux_2_17_x86_64"}),
        )

    def test_expand_is_a_cross_product_of_all_three_parts(self):
        got = self.m.expand_tags("py2.py3-none.abi3-any.linux_x86_64")
        self.assertEqual(len(got), 2 * 2 * 2)
        self.assertIn("py2-none-any", got)
        self.assertIn("py3-abi3-linux_x86_64", got)
        self.assertNotIn("py3-abi3-any.linux_x86_64", got)

    def test_expand_rejects_malformed(self):
        for bad in ["", "cp39-abi3", "cp39-abi3-", "-abi3-win_amd64", "cp39-abi3-win_amd64-x", "cp39-abi3-win_amd64.", "cp39..cp38-abi3-any", "cp39-abi3-win amd64", "cp39-abi3-win-amd64", "?"]:
            with self.subTest(bad=bad):
                with self.assertRaises(ValueError):
                    self.m.expand_tags(bad)

    def test_wheel_file_tags_reads_only_exact_tag_headers(self):
        text = WHEEL_HEAD + "Tag: cp39-abi3-win_amd64\nX-Tag: cp39-abi3-linux_x86_64\n  Tag: py3-none-any\nGenerator2: Tag: a-b-c\n"
        # an indented line is a header continuation in RFC 822 terms, not a header: it must not be read as a Tag
        self.assertEqual(self.m.wheel_file_tags(text), frozenset({"cp39-abi3-win_amd64"}))

    def test_wheel_file_tags_expands_a_compressed_tag_line(self):
        self.assertEqual(self.m.wheel_file_tags(wheel_text("py2.py3-none-any")), frozenset({"py2-none-any", "py3-none-any"}))

    def test_wheel_file_tags_tolerates_crlf_and_spaces(self):
        self.assertEqual(self.m.wheel_file_tags("Tag:   cp39-abi3-win_amd64  \r\nWheel-Version: 1.0\r\n"), frozenset({"cp39-abi3-win_amd64"}))

    def test_tag_mismatch_none_when_equal(self):
        self.assertIsNone(self.m.tag_mismatch("cp39-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64", MANYLINUX_WHEEL))
        self.assertIsNone(self.m.tag_mismatch("cp39-abi3-win_amd64", WIN_WHEEL))
        self.assertIsNone(self.m.tag_mismatch("cp39-abi3-macosx_11_0_arm64", MACOS_WHEEL))

    def test_tag_mismatch_names_missing_and_extra(self):
        msg = self.m.tag_mismatch("cp39-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64", wheel_text("cp39-abi3-manylinux_2_17_x86_64", "cp39-abi3-win_amd64"))
        self.assertIsNotNone(msg)
        self.assertIn("cp39-abi3-manylinux2014_x86_64", msg)  # missing from WHEEL
        self.assertIn("cp39-abi3-win_amd64", msg)  # not in the filename

    def test_tag_mismatch_reports_malformed_input_as_text_not_an_exception(self):
        self.assertIsNotNone(self.m.tag_mismatch("?", WIN_WHEEL))
        self.assertIsNotNone(self.m.tag_mismatch("cp39-abi3-win_amd64", wheel_text("win_amd64")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
