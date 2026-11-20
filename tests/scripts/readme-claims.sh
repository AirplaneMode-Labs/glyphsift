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
#  C. T3-S5-03, rewritten after the owner decision of 20 Nov 2026: the throughput table in the README (all five timings, the demo line, the
#     header's input size, machine and operating system), the commit, date, Node and Chrome versions it names, and the benchmark time next to the
#     reproduce command are the figures of the raw files committed under docs/benchmarks/ (throughput-m5pro-48gb.json,
#     demo-1mib-m5pro-48gb.json, score-vs-noise.provenance.json). They no longer depend on a log outside the repository, so
#     this section runs on every checkout, CI included. A README figure with no matching value in those files fails.
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

echo "== C. the throughput table and the benchmark time equal the raw files in docs/benchmarks/"
RAW_T=docs/benchmarks/throughput-m5pro-48gb.json
RAW_D=docs/benchmarks/demo-1mib-m5pro-48gb.json
RAW_S=docs/benchmarks/score-vs-noise.provenance.json
for f in "$RAW_T" "$RAW_D" "$RAW_S"; do
  if [ -f "$f" ]; then ok "$f is committed"; else fail "$f is committed"; fi
done
cat > "${TMPDIR:-/tmp}/readme-claims-c-$$.mjs" <<'JS'
import { readFileSync } from "node:fs";
const [, , readmePath, tPath, dPath, sPath] = process.argv;
const R = readFileSync(readmePath, "utf8");
const T = JSON.parse(readFileSync(tPath, "utf8"));
const D = JSON.parse(readFileSync(dPath, "utf8"));
const S = JSON.parse(readFileSync(sPath, "utf8"));
const lines = R.split("\n");
const cells = (l) => (l ? l.split("|").slice(1, -1).map((c) => c.trim()) : []);
const rowStarting = (prefix) => lines.find((l) => l.startsWith(prefix));
const best = (id) => T.data.results.find((r) => r.id === id)?.best_ms;
const n = (v) => v.toLocaleString("en-US");
const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const day = (iso) => { const d = new Date(iso); return `${d.getUTCDate()} ${months[d.getUTCMonth()]} ${d.getUTCFullYear()}`; };
const out = [];
const add = (name, want, got) => out.push([name, String(want), String(got ?? "")]);
const header = cells(lines.find((l) => l.startsWith("| Throughput on about 1 MiB of the synthetic corpus")));
const inp = T.data.input;
add("the table header names the input of throughput-m5pro-48gb.json", `Throughput on about 1 MiB of the synthetic corpus (${n(inp.bytes)} bytes, ${n(inp.lines)} lines, ${n(inp.clusters)} clusters)`, header[0]);
add("the table header names the machine and operating system of the raw file", `${T.machine} (${T.environment.os})`, header[1]);
add("the table's 8 GB column is the unmeasured one", "8 GB Windows no-GPU laptop", header[2]);
const rows = [
  ["native `glyphsift check`", "native_check"],
  ["WASM `validate()` in Node 22", "wasm_validate"],
  ["WASM `score_ppm()` in Node 22", "wasm_score_ppm"],
  ["WASM `gate()` in Node 22", "wasm_gate"],
  ["native `glyphsift gate`", "native_gate"],
];
for (const [label, id] of rows) {
  const c = cells(rowStarting(`| ${label}, `));
  add(`README ${label} row equals the best of five in the raw file`, `${best(id)} ms`, c[1]);
  add(`README ${label} row is best of 5 like the raw file`, String(T.data.runs_per_measurement), (/best of (\d+)/.exec(c[0]) ?? [])[1]);
}
const demo = cells(rowStarting("| demo in Chrome: 1 MiB pasted, validated and rendered"));
add("README demo row equals the raw file's single run", `${n(D.data.paste_validate_render_ms)} ms (headless Chrome, one run, includes the ${n(D.data.heatmap_cluster_cap)}-cluster heatmap)`, demo[1]);
add("the demo raw file is one run", 1, D.data.runs);
const flat = R.split("\n").join(" ").replace(/\s+/g, " ");
const has = (name, frag) => add(name, "present", flat.includes(frag) ? "present" : `missing: ${frag}`);
has("README names the throughput raw file's commit, date, machine, system and Node", `(${day(T.date)}, commit ${T.commit.slice(0, 7)}, ${T.machine}, ${T.environment.os}, Node ${T.environment.node.replace(/^v/, "")})`);
has("README names the Chrome of the demo raw file", `Google Chrome ${D.environment.chrome}`);
has("README names the 1 MiB text's SHA-256 prefix", `SHA-256 \`${inp.sha256.slice(0, 8)}...\``);
has("README gives the benchmark time of the reproduce command", `the release binary takes ${S.data.bench_wall_clock_ms_best} ms, best of three runs on the ${S.machine}`);
for (const f of ["docs/benchmarks/throughput-m5pro-48gb.json", "docs/benchmarks/demo-1mib-m5pro-48gb.json", "docs/benchmarks/score-vs-noise.provenance.json", "docs/benchmarks/wasm-linearity-m5pro-48gb.json", "docs/benchmarks/README.md"]) has(`README names ${f}`, f);
add("the throughput raw file measured the commit's own build inputs", false, T.build_inputs_modified);
add("the demo raw file measured the commit's own build inputs", false, D.build_inputs_modified);
process.stdout.write(JSON.stringify(out));
JS
CJ=$(node "${TMPDIR:-/tmp}/readme-claims-c-$$.mjs" "$README" "$RAW_T" "$RAW_D" "$RAW_S" 2>&1)
CSTATUS=$?
rm -f "${TMPDIR:-/tmp}/readme-claims-c-$$.mjs"
if [ "$CSTATUS" -ne 0 ]; then
  fail "the README table and the raw files could be compared (node said: $(printf '%s' "$CJ" | head -3 | tr '\n' ' '))"
else
  NC=$(printf '%s' "$CJ" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(String(JSON.parse(s).length)))')
  for i in $(seq 0 $((NC - 1))); do
    PAIR=$(printf '%s' "$CJ" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const [a,b,c]=JSON.parse(s)[Number(process.argv[1])];process.stdout.write([a,b,c].join("\u001f"))})' "$i")
    IFS=$'\037' read -r NAME WANT GOT <<< "$PAIR"
    # the separator is U+001F, not U+0001 (bash uses that one inside its own expansions); a pair that did not split must fail, never pass as two empty strings
    if [ -z "$WANT" ]; then fail "$i: the pair was read as name, wanted value and README value (got '$NAME')"; else expect_eq "$NAME" "$WANT" "$GOT"; fi
  done
  if [ "$NC" -ge 20 ]; then ok "compared $NC README claims with the raw files"; else fail "compared at least 20 README claims with the raw files (compared $NC)"; fi
fi

finish
