#!/usr/bin/env bash
# Run every script test in tests/scripts (each *.sh except this file and lib.sh) and fail if any fails.
# CI's packaging job runs this after scripts/build-wasm.sh and scripts/package-npm.sh.
#
#   tests/scripts/run-all.sh
#
# Each test prints one line per check and ends with "N passed, M failed"; a test that prints "SKIP" and
# exits 0 counts as passed (its reason is in the output). Nothing here publishes anything.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
FAILED=0
RAN=0
for t in "$HERE"/*.sh; do
  name=$(basename "$t")
  case "$name" in lib.sh|run-all.sh) continue ;; esac
  RAN=$((RAN+1))
  echo "=== $name"
  if bash "$t"; then echo "=== $name: ok"; else echo "=== $name: FAILED"; FAILED=$((FAILED+1)); fi
done
echo "script tests: $RAN run, $FAILED failed"
[ "$FAILED" -eq 0 ]
