#!/usr/bin/env bash
# CI run 44325740893: `wheel and sdist (ubuntu-latest)` failed on one line of tests/python/check_wheel.py, "WHEEL
# records the same platform tag as the filename". A manylinux wheel's filename carries a compressed tag set
# (cp39-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64, PEP 425) and its WHEEL file one Tag line per expanded tag;
# the old check looked for the compressed name as a literal string, which maturin never writes. macOS and Windows
# tags have no dot, so only the Linux leg could see it, and the Mac that develops this repository has no Linux wheel.
#
# This test runs tests/python/test_check_wheel.py, which builds synthetic wheels (a macOS one, a win_amd64 one and a
# compressed manylinux one, plus the cases that must still fail) and runs the real check on them, so the fault
# reproduces on any machine. Written before the fix (red log: the manylinux case failed on macOS, as in CI).
#
# CHECK_WHEEL_SCRIPT (an absolute path) runs the suite against another copy of check_wheel.py, for the red log:
#   git show HEAD:tests/python/check_wheel.py > "$X/check_wheel.py" && CHECK_WHEEL_SCRIPT=$X/check_wheel.py tests/scripts/check-wheel-tags.sh
# A missing python is a failure, not a skip: this test is the only proof of the Linux tag rule on a machine without
# a Linux wheel. No network call; nothing is written outside a temporary directory the test makes and removes.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

PY=${PYTHON:-}
if [ -z "$PY" ]; then
  for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1; then PY=$c; break; fi
  done
fi
if [ -z "$PY" ]; then
  fail "python not found: tests/python/test_check_wheel.py cannot run"
  finish
  exit
fi

OUT=$("$PY" -I "$REPO/tests/python/test_check_wheel.py" 2>&1)
RC=$?
expect_eq "tests/python/test_check_wheel.py exits 0" 0 "$RC"
if [ "$RC" -ne 0 ]; then printf '%s\n' "$OUT" | tail -60; fi

# The suite must really have run the three platform cases (a renamed or emptied test file must not pass quietly).
for t in test_macos_wheel_passes test_win_amd64_wheel_passes test_compressed_manylinux_name_passes test_not_a_substring_match_longer_platform; do
  expect_eq "$t ran and passed" 1 "$(printf '%s\n' "$OUT" | grep -cE "^$t \(.*\) \.\.\. ok$")"
done
RAN=$(printf '%s\n' "$OUT" | sed -n 's/^Ran \([0-9][0-9]*\) tests\{0,1\} in .*/\1/p')
expect_eq "at least 20 tests ran (ran ${RAN:-0})" 1 "$([ "${RAN:-0}" -ge 20 ] && echo 1 || echo 0)"

finish
