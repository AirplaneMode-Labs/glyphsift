#!/usr/bin/env bash
# `producer | grep -q pattern` under `set -o pipefail` is a false negative whenever the producer writes after the first match (CI run 44651027362, job
# "packaging dry runs", Ubuntu 26.04): tests/scripts/release-doc.sh ran
#     sed -n '/^## Status/,/^## Install/p' README.md | grep -qF "$VERSION"
# The Status section is 9438 bytes and "0.1.3" is in its first 120. GNU sed writes to a pipe in 4096-byte blocks; grep -q exits on the first block, sed's next
# write meets a closed pipe ("sed: couldn't flush stdout: Broken pipe", and a nonzero status that pipefail reports), and the check said the README did not name
# 0.1.3. GitHub Actions starts steps with SIGPIPE ignored (the runner is a Node process and children inherit the setting), so the producer gets EPIPE and an error
# message; with the default SIGPIPE it is killed and the status is 141. Either way the pipeline fails. It passed on the Mac because BSD sed wrote the section in one
# write before grep had read anything: whether the producer outlives the match depends on the buffer sizes and on scheduling, so no run proves the line safe.
#
# The fix is `gq` (tests/scripts/lib.sh): grep without -q, with the output discarded, so it reads to the end of its input and the producer never meets a closed pipe.
# This test (A) reproduces the condition on the real README with a producer that deliberately outlives the match, in both SIGPIPE modes, and (B) refuses a new
# `| grep -q` (or `| grep -m N`, which stops early the same way) in the shell scripts and workflow files.
#
#   tests/scripts/pipefail-grep-q.sh
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1

VERSION=$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
SECTION=$(sed -n '/^## Status/,/^## Install/p' README.md)
case "$SECTION" in *"$VERSION"*) ok "the README Status section names $VERSION (the data of the reproduction)" ;; *) fail "the README Status section names $VERSION" ;; esac
expect_eq "the Status section is long enough to need more than one 4096-byte write" 1 "$([ "${#SECTION}" -gt 4096 ] && echo 1 || echo 0)"

echo "== A. a producer that outlives the match"
# throttled: the section line by line with a pause after each, so the producer is still writing when the consumer has gone; like sed and cat, it fails when a write fails
throttled() { local line; while IFS= read -r line; do printf '%s\n' "$line" || return 1; sleep 0.001; done <<<"$SECTION"; }
# in_mode <default|ignored> <function and arguments...>: runs a pipeline under pipefail in a subshell, with SIGPIPE at its default or ignored as in Actions
in_mode() { local mode=$1; shift; ( set -o pipefail; [ "$mode" = ignored ] && trap '' PIPE; "$@" ); }
via_gq()      { throttled | gq -F "$VERSION"; }
via_gq_miss() { throttled | gq -F 'a sentence the README does not hold'; }
via_gq_x()    { printf 'a\nab\n' | gq -x a; }
via_gq_x_miss() { printf 'ab\n' | gq -x a; }
via_gq_E()    { printf 'x 0.1.3 y\n' | gq -E '0\.[0-9]+\.[0-9]+'; }
for mode in default ignored; do
  in_mode "$mode" via_gq 2>/dev/null;  expect_eq "gq finds the version in the throttled section, SIGPIPE $mode (the pipeline status is 0)" 0 "$?"
  in_mode "$mode" via_gq_miss 2>/dev/null; expect_eq "gq still reports a miss, SIGPIPE $mode (status 1)" 1 "$?"
done
in_mode default via_gq_x 2>/dev/null;      expect_eq "gq passes -x through (an exact line matches)" 0 "$?"
in_mode default via_gq_x_miss 2>/dev/null; expect_eq "gq passes -x through (a longer line does not match)" 1 "$?"
in_mode default via_gq_E 2>/dev/null;      expect_eq "gq passes -E through" 0 "$?"
OUT=$(throttled | gq -F "$VERSION" 2>&1); expect_eq "gq prints nothing" "" "$OUT"
# The hazard itself, for the record. Not an assertion: a shell where the producer happens to win would make it a false red. It is what the lint in B exists for.
unsafe() { throttled | grep -qF "$VERSION"; }
for mode in default ignored; do
  in_mode "$mode" unsafe 2>/dev/null; rc=$?
  echo "note - the same pipeline with grep -q, SIGPIPE $mode: status $rc ($([ "$rc" -eq 0 ] && echo 'the producer won here; not a proof of safety' || echo 'the false negative of CI run 44651027362'))"
done

echo "== B. no pipeline into grep -q (or grep -m N) in a script that may run under pipefail"
# The pattern: a pipe, then grep/egrep/fgrep with a flag cluster holding q or m (-q, -qF, -qxF, -m1), or --quiet, --silent, --max-count.
HAZARD='\|[[:space:]]*[ef]?grep[[:space:]]+(-[A-Za-z]*[qm]|--quiet|--silent|--max-count)'
# hazards <files...>: file:line:text of every hit outside a comment line
hazards() { grep -nHE "$HAZARD" "$@" 2>/dev/null | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' ; true; }
BAD1='tail -n 5 log | grep -qF done'
BAD2='printf x | grep -m1 x'
OK1='tail -n 5 log | gq -F done'
OK2='grep -qF done log'
OK3='  # a comment: sed -n p f | grep -q x'
expect_eq "the lint sees a pipeline into grep -qF and into grep -m1, and nothing else of five lines" 2 "$(printf '%s\n' "$BAD1" "$BAD2" "$OK1" "$OK2" "$OK3" | hazards - | grep -c '')"
FILES=(tests/scripts/*.sh scripts/*.sh scripts/release/*.sh .github/workflows/*.yml)
# this file holds the hazard on purpose (the 'unsafe' function above) and its self-test lines
LIST=()
for f in "${FILES[@]}"; do case "$f" in tests/scripts/pipefail-grep-q.sh) ;; *) LIST+=("$f") ;; esac; done
HITS=$(hazards "${LIST[@]}")
expect_eq "no shell script or workflow pipes into grep -q or grep -m N (use gq from tests/scripts/lib.sh, or grep >/dev/null)" "" "$HITS"
if [ -n "$HITS" ]; then printf '%s\n' "$HITS" | sed 's/^/    /' | head -60; fi
COVERED=0
for want in tests/scripts/release-doc.sh scripts/package-npm.sh scripts/release/publish-dry-run.sh .github/workflows/ci.yml .github/workflows/publish.yml; do
  for f in "${LIST[@]}"; do [ "$f" = "$want" ] && { COVERED=$((COVERED+1)); break; }; done
done
expect_eq "the lint covers the test scripts, the build scripts, the release scripts and both workflows" 5 "$COVERED"
finish
