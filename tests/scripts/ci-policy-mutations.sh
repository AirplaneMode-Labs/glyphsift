#!/usr/bin/env bash
# Sprint 7, fix round 1 (BUG-T3-S7-07 and the other FR1 policy rules): ci-policy.sh must go RED when a workflow or release-script rule is broken. The driver
# (tests/scripts/ci-policy-mutations.py) copies the workflows and the release scripts to a scratch directory, applies one mutation at a time, runs ci-policy.sh on
# the copy (WF=, RELD=) and expects a failure; a control run on the unmutated copy must pass. It never touches the real files.
#
#   tests/scripts/ci-policy-mutations.sh
set -uo pipefail
. "$(dirname "$0")/lib.sh"
PY=${PYTHON:-python3}
command -v "$PY" >/dev/null 2>&1 || { fail "python3 not found: the mutation driver needs it"; finish; exit 1; }
"$PY" -I "$REPO/tests/scripts/ci-policy-mutations.py" "$REPO"
