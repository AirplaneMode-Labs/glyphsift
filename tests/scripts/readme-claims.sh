#!/usr/bin/env bash
# README claims that a reader or a tester checks against another file (Sprint 5, fix round 1).
#
#   tests/scripts/readme-claims.sh
#
#  A. BUG-T1-S5-05 / T3-S5-04: the first line of the README's "## Status" section is the Sprint status line, verbatim
#     and on one line: the same text the demo renders in #sprint-status, that tests/demo/check_demo.mjs pins and that
#     site/data/demos.json carries. The longer narrative may follow it. If STATUS_LINE_FILE names a file (the
#     lane's status-line.txt, which is what D5 copies into site/data/demos.json), or ../evidence/sprint-7/D3/status-line.txt
#     exists beside the repository, the README must equal that file's line too; on a CI checkout there is no such file
#     and the output says so.
#  B. T3-S5-15: in the Benchmarks section every cell of an 8 GB column reads exactly "not measured on 8 GB", and no
#     cell anywhere in that section reads a bare "not measured".
#  C. T3-S5-03: the throughput figures in the README and the CHANGELOG are the figures of the log they cite,
#     evidence/sprint-5/D3/green/throughput.log. The log lives in the sprint scratch folder until the architect
#     copies it: THROUGHPUT_LOG names it, or ../evidence/sprint-5/D3/green/throughput.log exists beside the
#     repository. Without a log, the README and the CHANGELOG must still agree with each other.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1
README=README.md
CHANGELOG=CHANGELOG.md
DEMO=demo/index.html
CHECK=tests/demo/check_demo.mjs
for f in "$README" "$CHANGELOG" "$DEMO" "$CHECK"; do [ -f "$f" ] || { echo "error: $f not found" >&2; exit 1; }; done
command -v node >/dev/null || { fail "node not found: readme-claims.sh needs Node 22"; finish; exit 1; }

echo "== A. the README's Status section starts with the status line, verbatim"
cat > "${TMPDIR:-/tmp}/readme-claims-$$.mjs" <<'JS'
import { readFileSync } from "node:fs";
const [, , readme, demo] = process.argv;
const out = {};
const r = readFileSync(readme, "utf8").split("\n");
const i = r.findIndex((l) => l === "## Status");
out.statusHeading = i >= 0;
let first = "";
for (let k = i + 1; i >= 0 && k < r.length; k++) { if (r[k].trim() !== "") { first = r[k]; break; } }
out.readmeFirst = first;
const m = /<p class="status" id="sprint-status">([^<]*)<\/p>/.exec(readFileSync(demo, "utf8"));
out.demo = m ? m[1] : null;
process.stdout.write(JSON.stringify(out));
JS
J=$(node "${TMPDIR:-/tmp}/readme-claims-$$.mjs" "$README" "$DEMO")
rm -f "${TMPDIR:-/tmp}/readme-claims-$$.mjs"
jget() { printf '%s' "$J" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const v=JSON.parse(s)[process.argv[1]];process.stdout.write(v===null||v===undefined?"":String(v))})' "$1"; }
HEADING=$(jget statusHeading)
README_FIRST=$(jget readmeFirst)
DEMO_LINE=$(jget demo)
expect_eq "the README has a '## Status' heading" true "$HEADING"
expect_eq "the demo has a #sprint-status line without markup or entities" 0 "$(printf '%s' "$DEMO_LINE" | grep -c '[&<>]' | tr -d ' ')"
if [ -n "$DEMO_LINE" ] && [ "$README_FIRST" = "$DEMO_LINE" ]; then ok "the first line of the README Status section is exactly the demo's status line"
else fail "the first line of the README Status section is exactly the demo's status line (README: '$(printf '%s' "$README_FIRST" | cut -c1-90)...')"; fi
case "$README_FIRST" in "Sprint 7 (20 Nov 2026): Working: "*) ok "the README status line has the form 'Sprint 7 (20 Nov 2026): Working: <...>. Not yet: <...>.'" ;; *) fail "the README status line has the form 'Sprint 7 (20 Nov 2026): Working: <...>. Not yet: <...>.'" ;; esac
case "$README_FIRST" in *". Not yet: "*) ok "the README status line has a 'Not yet:' part" ;; *) fail "the README status line has a 'Not yet:' part" ;; esac
case "$README_FIRST" in *"not measured on 8 GB"*) ok "the README status line says 'not measured on 8 GB'" ;; *) fail "the README status line says 'not measured on 8 GB'" ;; esac
expect_eq "the README status line is one line (no hard wrap) ending with a full stop" 1 "$(printf '%s' "$README_FIRST" | grep -c '\.$' | tr -d ' ')"
expect_eq "tests/demo/check_demo.mjs pins the same line" 1 "$(grep -cF -- "$README_FIRST" "$CHECK" | tr -d ' ' | awk '{print ($1 >= 1) ? 1 : 0}')"
SLF=${STATUS_LINE_FILE:-}
[ -z "$SLF" ] && [ -f "$REPO/../evidence/sprint-7/D3/status-line.txt" ] && SLF=$REPO/../evidence/sprint-7/D3/status-line.txt
if [ -n "$SLF" ] && [ -f "$SLF" ]; then
  FILE_LINE=$(head -1 "$SLF")
  expect_eq "status-line.txt ($SLF) equals the README's first Status line" "$FILE_LINE" "$README_FIRST"
  expect_eq "status-line.txt equals the demo's status line" "$FILE_LINE" "$DEMO_LINE"
else
  echo "na   - status-line.txt: not applicable here (no STATUS_LINE_FILE and no ../evidence/sprint-7/D3/status-line.txt; the demo's line, which check_demo.mjs pins, is the in-repo source)"
fi

echo "== D. TD-116: the live demo is in the first screen, and the quick start follows the Status"
LD_LINE=$(head -12 "$README" | grep -nxF 'Live demo: https://airplanemode-labs.github.io/glyphsift/' | head -1 | cut -d: -f1)
if [ -n "$LD_LINE" ]; then ok "the README has the exact line 'Live demo: https://airplanemode-labs.github.io/glyphsift/' (line $LD_LINE, within the first 12)"; else fail "the README has the exact line 'Live demo: https://airplanemode-labs.github.io/glyphsift/' within its first 12 lines"; fi
expect_eq "the README's first line is the title '# glyphsift'" "# glyphsift" "$(head -1 "$README")"
expect_eq "the placeholder-name note is within the first 14 lines" 1 "$(head -14 "$README" | grep -c 'placeholder scope' | awk '{print ($1 >= 1) ? 1 : 0}')"
expect_eq "the README sections of the Sprint 7 convention are in order" "Status|Try it in two minutes|Install|Quick start|How it works|Contracts|Demo|Benchmarks|Limitations|Security and privacy|Develop|Licence" "$(grep -E '^## ' "$README" | sed 's/^## //' | tr '\n' '|' | sed 's/|$//')"

echo "== B. every 8 GB cell in the Benchmarks section reads 'not measured on 8 GB'"
BENCH=$(awk '/^## Benchmarks/{on=1; next} on && /^## /{exit} on{print}' "$README")
if [ -n "$BENCH" ]; then ok "the README has a Benchmarks section"; else fail "the README has a Benchmarks section"; fi
# Walk the table rows: a header row whose last cell mentions 8 GB makes every body row of that table need the exact text there.
BAD8=0; NCELL=0; BAREROW=0
TABLE_8GB=0
while IFS= read -r line; do
  case "$line" in
    '|'*)
      cells=$(printf '%s' "$line" | awk -F'|' '{for (i=2;i<NF;i++){c=$i; gsub(/^[ \t]+|[ \t]+$/,"",c); print c}}')
      last=$(printf '%s\n' "$cells" | tail -1)
      if printf '%s' "$line" | gq -E '^\|[ :|-]+\|$'; then continue; fi          # the |---|---| separator row
      if [ "$TABLE_8GB" = "0" ] && printf '%s' "$last" | gq '8 GB'; then TABLE_8GB=1; continue; fi   # the header row of an 8 GB table
      if [ "$TABLE_8GB" = "1" ]; then
        NCELL=$((NCELL+1))
        if [ "$last" != "not measured on 8 GB" ]; then BAD8=$((BAD8+1)); echo "    8 GB cell reads '$last': $(printf '%s' "$line" | cut -c1-80)"; fi
      fi
      if printf '%s\n' "$cells" | gq -x 'not measured'; then BAREROW=$((BAREROW+1)); echo "    bare 'not measured' cell: $(printf '%s' "$line" | cut -c1-80)"; fi
      ;;
    *) TABLE_8GB=0 ;;
  esac
done <<< "$BENCH"
if [ "$NCELL" -ge 20 ]; then ok "found $NCELL 8 GB cells in the Benchmarks tables"; else fail "found at least 20 8 GB cells in the Benchmarks tables (found $NCELL)"; fi
expect_eq "every 8 GB cell reads exactly 'not measured on 8 GB'" 0 "$BAD8"
expect_eq "no table cell in the Benchmarks section is a bare 'not measured'" 0 "$BAREROW"
expect_eq "the Benchmarks prose says 'not measured on 8 GB'" 1 "$(printf '%s\n' "$BENCH" | grep -c 'not measured on 8 GB' | awk '{print ($1 >= 1) ? 1 : 0}')"

echo "== C. throughput figures equal the log they cite"
THROUGHPUT_LOG_PATH=""
for cand in "${THROUGHPUT_LOG:-}" "$REPO/../evidence/sprint-5/D3/green/throughput.log"; do
  if [ -n "$cand" ] && [ -f "$cand" ]; then THROUGHPUT_LOG_PATH=$cand; break; fi
done
best() { grep -E "$1" "$THROUGHPUT_LOG_PATH" | sed -n 's/.*best \([0-9][0-9]*\) ms.*/\1/p' | head -1; }
# README: table rows
R_GATE=$(grep -E '^\| WASM `gate\(\)` in Node 22' "$README" | awk -F'|' '{print $3}' | grep -oE '[0-9][0-9,]*' | head -1)
R_NGATE=$(grep -E '^\| native `glyphsift gate`' "$README" | awk -F'|' '{print $3}' | grep -oE '[0-9][0-9,]*' | head -1)
# README: the sentence "the same run measured `validate()` at N ms, `score_ppm()` at N ms and the native `check` at N ms"
SENT=$(tr '\n' ' ' < "$README" | grep -oE 'the same run measured `validate\(\)` at [0-9]+ ms, `score_ppm\(\)` at [0-9]+ ms and the native `check` at [0-9]+ ms' | head -1)
R_VAL=$(printf '%s' "$SENT" | sed -n 's/.*`validate()` at \([0-9]*\) ms.*/\1/p')
R_SCORE=$(printf '%s' "$SENT" | sed -n 's/.*`score_ppm()` at \([0-9]*\) ms.*/\1/p')
R_CHECK=$(printf '%s' "$SENT" | sed -n 's/.*`check` at \([0-9]*\) ms.*/\1/p')
# CHANGELOG: "WASM `gate()` takes N ms on the 1 MiB corpus against N ms for `validate()`"
CSENT=$(tr '\n' ' ' < "$CHANGELOG" | grep -oE 'WASM `gate\(\)` takes [0-9]+ ms on the 1 MiB corpus against [0-9]+ ms for `validate\(\)`' | head -1)
C_GATE=$(printf '%s' "$CSENT" | sed -n 's/.*takes \([0-9]*\) ms.*/\1/p')
C_VAL=$(printf '%s' "$CSENT" | sed -n 's/.*against \([0-9]*\) ms.*/\1/p')
for pair in "R_GATE:the README gate() row" "R_NGATE:the README native gate row" "R_VAL:the README validate() figure" "R_SCORE:the README score_ppm() figure" "R_CHECK:the README native check figure" "C_GATE:the CHANGELOG gate() figure" "C_VAL:the CHANGELOG validate() figure"; do
  v=${pair%%:*}; d=${pair#*:}
  if [ -n "${!v}" ]; then ok "$d is stated (${!v} ms)"; else fail "$d is stated"; fi
done
expect_eq "README and CHANGELOG give the same gate() figure" "$R_GATE" "$C_GATE"
expect_eq "README and CHANGELOG give the same validate() figure" "$R_VAL" "$C_VAL"
if [ -n "$THROUGHPUT_LOG_PATH" ]; then
  echo "     log: $THROUGHPUT_LOG_PATH"
  L_GATE=$(best 'WASM gate\(\)')
  L_VAL=$(best 'WASM validate\(\)')
  L_SCORE=$(best 'WASM score_ppm\(\)')
  L_CHECK=$(best 'native glyphsift check')
  L_NGATE=$(best 'native glyphsift gate')
  for pair in "L_GATE" "L_VAL" "L_SCORE" "L_CHECK" "L_NGATE"; do
    if [ -n "${!pair}" ]; then ok "the log has $pair (${!pair} ms)"; else fail "the log has $pair"; fi
  done
  expect_eq "README gate() row equals the log" "$L_GATE" "$R_GATE"
  expect_eq "README native gate row equals the log" "$L_NGATE" "$R_NGATE"
  expect_eq "README validate() figure equals the log" "$L_VAL" "$R_VAL"
  expect_eq "README score_ppm() figure equals the log" "$L_SCORE" "$R_SCORE"
  expect_eq "README native check figure equals the log" "$L_CHECK" "$R_CHECK"
  expect_eq "CHANGELOG gate() figure equals the log" "$L_GATE" "$C_GATE"
  expect_eq "CHANGELOG validate() figure equals the log" "$L_VAL" "$C_VAL"
else
  echo "na   - throughput log: not applicable here (no THROUGHPUT_LOG and no ../evidence/sprint-5/D3/green/throughput.log); README and CHANGELOG were compared with each other only"
fi
expect_eq "the README names the log it cites" 1 "$(grep -c 'evidence/sprint-5/D3/green/throughput.log' "$README" | awk '{print ($1 >= 1) ? 1 : 0}')"

finish
