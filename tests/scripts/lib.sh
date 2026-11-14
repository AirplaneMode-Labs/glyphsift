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
