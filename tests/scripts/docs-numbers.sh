#!/usr/bin/env bash
# D3-03: docs/what-glyphsift-measures.md quotes only numbers that are in committed files (tests/docs_numbers.py re-reads each one).
#
#   tests/scripts/docs-numbers.sh
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1
PY=${PYTHON:-python3}
command -v "$PY" >/dev/null 2>&1 || { fail "$PY is available"; finish; exit $?; }
"$PY" -I tests/docs_numbers.py
expect_eq "tests/docs_numbers.py passes" 0 "$?"
finish
