#!/usr/bin/env bash
# BUG-T2-S5-14 (run_gate_native.mjs part): when the CLI cannot be run (for example CARGO_TARGET_DIR points elsewhere, so
# target/release/glyphsift does not exist), tests/determinism/run_gate_native.mjs exits non-zero with
# "cannot run <cli path>: <error message>" instead of throwing a TypeError from `r.stdout.toString()`.
#
#   tests/scripts/gate-native-error.sh
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1
command -v node >/dev/null || { fail "node is installed (Node 22 is required)"; finish; exit $?; }

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/glyphsift-gate-native.XXXXXX") || exit 1
cleanup() { case "$SCRATCH" in /*/glyphsift-gate-native.??????) rm -rf "$SCRATCH" ;; esac; }
trap cleanup EXIT
MISSING="$SCRATCH/no-such-dir/glyphsift"

node tests/determinism/run_gate_native.mjs --cli "$MISSING" > "$SCRATCH/out.txt" 2> "$SCRATCH/err.txt"
rc=$?
if [ "$rc" -ne 0 ]; then ok "a CLI that cannot be run exits non-zero (exit $rc)"; else fail "a CLI that cannot be run exits non-zero (exit 0)"; fi
if grep -q "TypeError" "$SCRATCH/err.txt" "$SCRATCH/out.txt"; then fail "no TypeError is thrown"; else ok "no TypeError is thrown"; fi
if grep -qF "cannot run " "$SCRATCH/err.txt" && grep -qF "no-such-dir" "$SCRATCH/err.txt"; then ok "the message names the CLI path ('cannot run <cli path>: ...')"; else fail "the message names the CLI path ('cannot run <cli path>: ...')"; fi
if grep -qE "cannot run .*: .*(ENOENT|no such file|not found)" "$SCRATCH/err.txt"; then ok "the message carries the error text"; else fail "the message carries the error text"; fi
[ "$rc" -eq 1 ] && ok "exit status is 1" || fail "exit status is 1 (got $rc)"
finish
