#!/usr/bin/env bash
# D3-04 (TD-117): the issue forms, the security contact and the contributing guide are what the Sprint 7 rules say.
#
#   tests/scripts/community-files.sh
#
#  A. .github/ISSUE_TEMPLATE/bug_report.yml and feature_request.yml carry the required no-real-documents checkbox, word for word, and ask for redaction;
#     config.yml turns blank issues off and links SECURITY.md; every form is valid YAML.
#  B. SECURITY.md says to report a vulnerability privately and never in a public issue, names the contact, and still states the test-key and no-telemetry facts.
#  C. CONTRIBUTING.md keeps the tests-first, determinism and synthetic-input rules, names the quick start and the release path, and says contributors never publish.
#  D. when the workspace has the drafts folder beside this repository (a lone checkout does not), drafts/good-first-issues/glyphsift.md holds 3 to 5 texts and none of
#     them says it was filed.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1
IT=.github/ISSUE_TEMPLATE
BOX="I have not attached any real, confidential or personal document (bank, legal, medical, identity). Any sample is synthetic or public."
echo "== A. issue forms"
for f in bug_report.yml feature_request.yml config.yml; do [ -f "$IT/$f" ] && ok "$IT/$f exists" || fail "$IT/$f exists"; done
for f in bug_report.yml feature_request.yml; do
  [ -f "$IT/$f" ] || continue
  expect_eq "$f: the checkbox text is exactly the agreed sentence" 1 "$(grep -cF -- "- label: \"$BOX\"" "$IT/$f")"
  expect_eq "$f: the checkbox is required" 1 "$(awk -v box="$BOX" 'index($0, box){f=1; next} f && /required: true/{print "1"; exit} f && /- label:|type:/{exit}' "$IT/$f")"
  expect_eq "$f: it is a checkboxes element" 1 "$(grep -cE '^[[:space:]]+- type: checkboxes' "$IT/$f" | awk '{print ($1 >= 1) ? 1 : 0}')"
  expect_eq "$f: it asks the reporter to redact anything private" 1 "$(grep -ciE 'redact' "$IT/$f" | awk '{print ($1 >= 1) ? 1 : 0}')"
  expect_eq "$f: it has a name, a description and a body" 3 "$(grep -cE '^(name|description|body):' "$IT/$f")"
done
if [ -f "$IT/config.yml" ]; then
  expect_eq "config.yml: blank issues are disabled" 1 "$(grep -cx 'blank_issues_enabled: false' "$IT/config.yml")"
  expect_eq "config.yml: a contact link points at this repository's SECURITY.md" 1 "$(grep -cF 'url: https://github.com/AirplaneMode-Labs/glyphsift/blob/main/SECURITY.md' "$IT/config.yml")"
fi
if command -v ruby >/dev/null 2>&1; then
  for f in bug_report.yml feature_request.yml config.yml; do
    [ -f "$IT/$f" ] || continue
    if ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$IT/$f" >/dev/null 2>&1; then ok "$f parses as YAML"; else fail "$f parses as YAML"; fi
  done
else
  echo "na   - YAML parse: ruby is not installed here; the text checks above still ran"
fi

echo "== B. SECURITY.md"
expect_eq "SECURITY.md says never to report a vulnerability in a public issue" 1 "$(tr '\n' ' ' < SECURITY.md | sed 's/  */ /g' | grep -ciE 'never in a public issue|not in a public issue' | awk '{print ($1 >= 1) ? 1 : 0}')"
expect_eq "SECURITY.md says to report privately" 1 "$(grep -ciE 'privately|private vulnerability' SECURITY.md | awk '{print ($1 >= 1) ? 1 : 0}')"
expect_eq "SECURITY.md keeps a contact" 1 "$(grep -c 'jtushar53@gmail.com' SECURITY.md | awk '{print ($1 >= 1) ? 1 : 0}')"
expect_eq "SECURITY.md keeps the RFC 8032 test-key statement" 1 "$(grep -c 'RFC 8032' SECURITY.md | awk '{print ($1 >= 1) ? 1 : 0}')"
expect_eq "SECURITY.md keeps the no-telemetry statement" 1 "$(grep -ci 'no telemetry' SECURITY.md | awk '{print ($1 >= 1) ? 1 : 0}')"

echo "== C. CONTRIBUTING.md"
cc() { if tr '\n' ' ' < CONTRIBUTING.md | sed 's/  */ /g' | grep -qF -- "$1"; then ok "CONTRIBUTING.md says $2"; else fail "CONTRIBUTING.md says $2 ($1)"; fi; }
cc "## Tests first" "tests first"
cc "## Determinism" "determinism"
cc "Synthetic inputs only" "synthetic inputs only"
cc "Try it in two minutes" "where the quick start is"
cc "tests/scripts/quickstart.sh" "which test runs the quick start"
cc "docs/RELEASING.md" "where the release steps are"
cc "Contributors never publish" "that contributors never publish"
cc "docs/release-keys.json" "that docs/release-keys.json is the owner's file"
cc ".github/ISSUE_TEMPLATE" "which issue forms exist"
cc "tests/scripts/run-all.sh" "how to run the script tests"

echo "== D. good-first-issue drafts (the workspace's drafts folder, when it is there)"
GF=$REPO/../drafts/good-first-issues/glyphsift.md
if [ -d "$REPO/../drafts" ] && [ ! -f "$GF" ]; then
  fail "the workspace has a drafts folder but drafts/good-first-issues/glyphsift.md is missing"
elif [ -f "$GF" ]; then
  N=$(grep -cE '^## [0-9]+\. ' "$GF")
  if [ "$N" -ge 3 ] && [ "$N" -le 5 ]; then ok "the draft holds $N texts (3 to 5)"; else fail "the draft holds 3 to 5 texts (found $N)"; fi
  expect_eq "the draft says it is a draft and that nothing is filed" 1 "$(grep -ciE 'draft' "$GF" | awk '{print ($1 >= 1) ? 1 : 0}')"
  expect_eq "the draft does not say anything was filed or posted" 0 "$(grep -iE 'filed as|issue #[0-9]|opened issue|posted to' "$GF" | grep -vciE 'never|not filed|nothing is filed')"
  expect_eq "no text asks for Tamil code" 0 "$(grep -ciE 'tamil (code|rules|implementation)' "$GF" | tr -d ' ')"
else
  echo "na   - the drafts folder is not beside this repository (a lone checkout); the workspace run checks it"
fi
finish
