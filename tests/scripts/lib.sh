#!/usr/bin/env bash
# Shared helpers for the script tests. Each test builds a scratch copy of the layout the script under
# test expects (scripts/, Cargo.toml, dist/), so nothing touches the real working tree and no network
# call is made. SCRIPTS_DIR overrides where the scripts come from (used to run a test against an older
# version of a script for the red log).
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPTS_DIR=${SCRIPTS_DIR:-$REPO/scripts}
FAILS=0
PASSES=0
ok()   { PASSES=$((PASSES+1)); echo "ok   - $1"; }
fail() { FAILS=$((FAILS+1)); echo "FAIL - $1"; }
# expect_eq <name> <want> <got>
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (want '$2', got '$3')"; fi; }
finish() { echo "$PASSES passed, $FAILS failed"; [ "$FAILS" -eq 0 ]; }

# ---- cargo test log parsing (S1-118 follow-up, CI run 44580204699) ---------------------------------------------------------
# The text of a cargo test log depends on the runner: the workflow sets CARGO_TERM_COLOR=always, which colours the status word
# of every `Running` line even when the output goes to a file (ESC[1mESC[92m     RunningESC[0m tests/corrupt.rs (...)), and
# Windows prints that line with backslashes and a .exe path. A literal search for "Running tests/corrupt.rs" matches neither.
# Parse a log only through these functions; tests/scripts/cargo-test-log.sh checks them on each runner's format.

# strip_ansi: stdin to stdout without ANSI escape sequences (colour, style and the other CSI finals) and without a trailing CR.
strip_ansi() { local esc cr; esc=$(printf '\033'); cr=$(printf '\r'); LC_ALL=C sed -e "s/${esc}\\[[0-9;]*[A-Za-z]//g" -e "s/${cr}\$//"; }

# cargo_bin_passed <log> <name>: the number of tests that passed in the binary of tests/<name>.rs, read from the first
# `test result: ok.` line after its `Running tests/<name>.rs (` line. Prints nothing when the binary did not run (no such
# Running line: cargo skips a target whose required feature is off, silently), when it printed no summary before the next
# Running or Doc-tests line (a crash), or when its summary is not `ok`. A binary that ran no test prints 0.
cargo_bin_passed() {
  strip_ansi < "$1" | awk -v b="tests/$2.rs" '
    /^ *(Running|Doc-tests) / { l = $0; gsub(/\\/, "/", l); f = (index(l, "Running " b " (") > 0); next }
    f && !d && /^test result:/ {
      if ($0 ~ /^test result: ok\./ && match($0, /[0-9]+ passed/)) print substr($0, RSTART, RLENGTH - 7)
      d = 1
    }'
}

# cargo_failed_total <log>: the sum of the `N failed` counts on every `test result:` line (0 for a log without one).
cargo_failed_total() { strip_ansi < "$1" | grep -E '^test result:' | grep -oE '[0-9]+ failed' | awk '{s+=$1} END{print s+0}'; }
