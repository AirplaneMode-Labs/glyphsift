#!/usr/bin/env bash
# Run every script test in tests/scripts (each *.sh except this file and lib.sh) and the --out containment unit
# tests (confine.test.mjs), and fail if any fails.
# CI's packaging job runs this after scripts/build-wasm.sh and scripts/package-npm.sh. The check job runs the
# containment pair (confine.test.mjs and release-manifest.sh) on its own on ubuntu, macos and windows.
#
#   tests/scripts/run-all.sh
#
# Each test prints one line per check and ends with "N passed, M failed"; a test that prints "SKIP" and
# exits 0 counts as passed (its reason is in the output). release-manifest.sh and confine.test.mjs never skip: a
# missing node or a link that cannot be made is a failure there. Nothing here publishes anything.
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
# Path-containment unit tests (path.win32 and an in-memory volume, then real links and hard links). Node is
# required: a missing node is a failure, not a skip, because this suite is what proves the Windows rules on a Mac.
RAN=$((RAN+1))
echo "=== confine.test.mjs"
if command -v node >/dev/null; then
  if node --test "$HERE/confine.test.mjs"; then echo "=== confine.test.mjs: ok"; else echo "=== confine.test.mjs: FAILED"; FAILED=$((FAILED+1)); fi
else
  echo "FAIL - node not found: confine.test.mjs cannot run (Node 22 is required)"; echo "=== confine.test.mjs: FAILED"; FAILED=$((FAILED+1))
fi
echo "script tests: $RAN run, $FAILED failed"
[ "$FAILED" -eq 0 ]
