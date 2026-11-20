#!/usr/bin/env bash
# BUG-T3-S7-01 / S1-130: `npm publish verified/<name>.tgz` is not a file path to npm: a spec of the form `a/b` is the GitHub shorthand user/repo, so npm would try to
# publish a third party's repository named verified/<name>.tgz. The argument must start with ./ (or be absolute). This test takes the argument out of
# .github/workflows/publish.yml and out of scripts/release/publish-dry-run.sh (they must be the same string) and asks npm's own npm-package-arg what it is: it must
# resolve as type 'file'. The old form is resolved too, and must come out as a hosted git spec, so the probe cannot pass by accident. The Node of the running shell
# supplies the module (tests/scripts/npm-package-arg-probe.cjs); a Node without it is a failure, not a skip.
#
#   tests/scripts/npm-publish-arg.sh
set -uo pipefail
. "$(dirname "$0")/lib.sh"
PUB=${PUB:-$REPO/.github/workflows/publish.yml}
DRY=${DRY:-$REPO/scripts/release/publish-dry-run.sh}
command -v node >/dev/null || { fail "node not found: Node 22 is required"; finish; exit 1; }
# the first argument after the first `npm publish ` on the first command line that has one (quotes removed)
arg_of() {
  grep -vE '^[[:space:]]*#' "$1" | grep -vE '^[[:space:]]*((- )?name:|echo |printf |note |die )' \
    | awk '{ i = index($0, "npm publish "); if (i == 0) next; r = substr($0, i + 12); sub(/^ +/, "", r); if (substr(r, 1, 1) == "\"") { j = index(substr(r, 2), "\""); print substr(r, 2, j - 1) } else { split(r, a, " "); print a[1] } exit }'
}
SAMPLE=airplanemode-glyphsift-0.1.3.tgz
resolve_sample() { local a=$1; printf '%s' "${a//\$(cat lists\/npm.txt)/$SAMPLE}"; }
WF_ARG=$(arg_of "$PUB"); DRY_ARG=$(arg_of "$DRY")
expect_eq "publish.yml has an npm publish line with an argument" 1 "$([ -n "$WF_ARG" ] && echo 1 || echo 0)"
expect_eq "the dry run's npm publish argument is the workflow's, character for character" "$WF_ARG" "$DRY_ARG"
WF_SPEC=$(resolve_sample "$WF_ARG")
expect_eq "the workflow's argument, with the list entry filled in, is ./verified/<tarball>" "./verified/$SAMPLE" "$WF_SPEC"
OUT=$(node "$REPO/tests/scripts/npm-package-arg-probe.cjs" "$WF_SPEC" "verified/$SAMPLE" "/abs/verified/$SAMPLE" 2>&1); RC=$?
if [ "$RC" -ne 0 ]; then
  fail "npm-package-arg could not be loaded from the running Node's npm: $OUT"
else
  printf '%s\n' "$OUT" | sed 's/^/    probe: /'
  expect_eq "npm resolves the workflow's argument as type 'file'" "file" "$(printf '%s\n' "$OUT" | awk -F'\t' -v s="$WF_SPEC" '$1 == s {print $2; exit}')"
  expect_eq "npm resolves a bare verified/<tarball> as a hosted GitHub spec (the S1-130 hazard the ./ prefix removes)" "git" "$(printf '%s\n' "$OUT" | awk -F'\t' -v s="verified/$SAMPLE" '$1 == s {print $2; exit}')"
  expect_eq "npm resolves an absolute path as type 'file'" "file" "$(printf '%s\n' "$OUT" | awk -F'\t' -v s="/abs/verified/$SAMPLE" '$1 == s {print $2; exit}')"
fi
finish
