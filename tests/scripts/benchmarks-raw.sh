#!/usr/bin/env bash
# Owner decision, 20 Nov 2026: every benchmark figure glyphsift quotes is published in this repository as a raw file under docs/benchmarks/, with the
# date, commit, machine and method it was measured with, and an index (docs/benchmarks/README.md) that says what each file is and how to reproduce it.
#
#   tests/scripts/benchmarks-raw.sh
#
# This test checks the files themselves; the figures that the README and docs/ quote from them are checked by tests/docs_numbers.py (score tables,
# hold counts, ratios and every `N ms`) and tests/scripts/readme-claims.sh (the throughput table). It checks, for every file in docs/benchmarks/:
#   A. the index README exists, carries the standing line about 8 GB laptops, lists every file in a table row with the file's date, short commit
#      and machine label, and prints the file's `command` exactly; no file is missing from the index and no listed file is missing from the folder.
#   B. every .json file has the envelope (schema glyphsift.benchmark/1, benchmark, date in UTC, a 40-hex commit, build_inputs_modified false,
#      worktree_clean, machine, environment, method, command, data); the machine label is model and RAM only (no path, no host name, no user name),
#      or the CI runners; nothing in the file is a builder path; no file is over 5 MB; no file has a CR.
#   C. the score CSV is byte-identical to docs/score-vs-noise.csv, and the provenance file holds its SHA-256, the SVG's, the row count and the corpus hash;
#      the other files name the corpus hash of bench/corpus/clean.txt; a throughput best is the fastest of its runs.
#   D. the sizes in docs/release.md for CI run 43667702791 are exactly the sizes in docs/benchmarks/ci-run-43667702791.json.
#   E. the checks themselves can fail: a scratch copy of the folder with one value changed, or one file unlisted, is refused.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1
command -v node >/dev/null || { fail "node not found: benchmarks-raw.sh needs Node 22"; finish; exit 1; }
B=docs/benchmarks

echo "== A-D. the committed raw files"
trap 'rm -f "${TMPDIR:-/tmp}/benchmarks-raw-$$.mjs"' EXIT
cat > "${TMPDIR:-/tmp}/benchmarks-raw-$$.mjs" <<'JS'
import { createHash } from "node:crypto";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { hostname, userInfo } from "node:os";
import { join } from "node:path";

const [, , repo, dir] = process.argv; // repo root, benchmarks folder (relative to the repo root)
const out = [];
const check = (name, ok, detail = "") => out.push([ok ? "ok" : "fail", detail && !ok ? `${name} (${detail})` : name]);
const read = (...p) => readFileSync(join(repo, ...p));
const sha = (buf) => createHash("sha256").update(buf).digest("hex");
const folder = join(repo, dir);
const files = readdirSync(folder).sort();
const index = readFileSync(join(folder, "README.md"), "utf8");
const jsons = files.filter((f) => f.endsWith(".json"));
const others = files.filter((f) => f !== "README.md" && !f.endsWith(".json"));

// ---- A. the index
check("the index README states that nothing here is measured on an 8 GB laptop unless a file says so", index.includes("Nothing here is measured on an 8 GB laptop unless a file says so"));
const flat = index.replace(/\s+/g, " ");
const rows = index.split("\n").filter((l) => l.startsWith("| `"));
const listed = rows.map((l) => /^\| `([^`]+)`/.exec(l)[1]).sort();
const want = files.filter((f) => f !== "README.md");
check(`the index table lists exactly the files of the folder (${want.join(", ")})`, JSON.stringify(listed) === JSON.stringify(want), `listed: ${listed.join(", ")}`);
check("the folder holds at least the eight raw files of 20 Nov 2026", want.length >= 8, `${want.length} files`);
const env8 = [];

for (const f of jsons) {
  const raw = readFileSync(join(folder, f), "utf8");
  let j;
  try {
    j = JSON.parse(raw);
  } catch (e) {
    check(`${f} is valid JSON`, false, e.message);
    continue;
  }
  const row = rows.find((l) => l.startsWith(`| \`${f}\``)) ?? "";
  // ---- B. the envelope
  check(`${f}: schema is glyphsift.benchmark/1`, j.schema === "glyphsift.benchmark/1");
  check(`${f}: benchmark is a name`, typeof j.benchmark === "string" && /^[a-z0-9-]+$/.test(j.benchmark), String(j.benchmark));
  check(`${f}: date is UTC to the second`, typeof j.date === "string" && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(j.date) && !Number.isNaN(Date.parse(j.date)), String(j.date));
  check(`${f}: commit is 40 hex digits`, typeof j.commit === "string" && /^[0-9a-f]{40}$/.test(j.commit), String(j.commit));
  check(`${f}: build_inputs_modified is false (the file describes the commit it names)`, j.build_inputs_modified === false);
  check(`${f}: worktree_clean is a boolean`, typeof j.worktree_clean === "boolean");
  const ci = typeof j.machine === "string" && /^GitHub-hosted CI runners \([a-z0-9, -]+\)$/.test(j.machine);
  const mac = typeof j.machine === "string" && /^[A-Za-z][A-Za-z0-9 ().+-]*, \d+ GB$/.test(j.machine);
  check(`${f}: machine is a CPU model and RAM (or the CI runners): '${j.machine}'`, ci || mac);
  // this host's and this user's names, unless they are the generic account names of a CI runner or a container (which the CI record names on purpose)
  const generic = new Set(["runner", "runneradmin", "root", "admin", "ubuntu", "user", "localhost"]);
  const me = [hostname(), userInfo().username].filter((x) => x && x.length >= 3 && !generic.has(x.toLowerCase()));
  check(`${f}: nothing in the file names this host or user`, !me.some((x) => raw.toLowerCase().includes(x.toLowerCase())), me.length ? "host or user name found" : "");
  check(`${f}: nothing in the file is a builder path`, !/\/Users\/|\/private\/|\/home\/|\/tmp\/|[A-Za-z]:\\\\/.test(raw));
  check(`${f}: environment is an object`, j.environment !== null && typeof j.environment === "object" && !Array.isArray(j.environment));
  check(`${f}: method and command are text`, typeof j.method === "string" && j.method.length > 40 && typeof j.command === "string" && j.command.length > 10);
  check(`${f}: data is an object`, j.data !== null && typeof j.data === "object" && !Array.isArray(j.data));
  check(`${f}: no CR and under 5 MB`, !raw.includes("\r") && statSync(join(folder, f)).size < 5 * 1024 * 1024);
  check(`${f}: ends with one newline and uses two-space JSON`, raw.endsWith("}\n") && raw === JSON.stringify(j, null, 2) + "\n");
  // ---- A. the index row and the command
  check(`${f}: its index row has the date ${String(j.date).slice(0, 10)}, the commit ${String(j.commit).slice(0, 7)} and the machine`, row.includes(String(j.date).slice(0, 10)) && row.includes("`" + String(j.commit).slice(0, 7) + "`") && row.includes(String(j.machine)), row.slice(0, 60));
  check(`${f}: its command appears on the index page exactly as recorded`, flat.includes(String(j.command).replace(/\s+/g, " ")) || index.includes(String(j.command)), String(j.command).slice(0, 60));
  if (/(^|, )8 GB$/.test(String(j.machine))) env8.push(f);
}
check("the index says no file is from an 8 GB laptop only while none is (a file whose machine ends in '8 GB' removes the sentence 'and no file does yet')", env8.length === 0 ? index.includes("and no file does yet") : !index.includes("and no file does yet"), env8.join(", "));

// the other files in the folder (the CSV copy)
for (const f of others) {
  const buf = readFileSync(join(folder, f));
  check(`${f}: under 5 MB, no CR`, buf.length < 5 * 1024 * 1024 && !buf.includes(13));
  const row = rows.find((l) => l.startsWith(`| \`${f}\``)) ?? "";
  const prov = JSON.parse(readFileSync(join(folder, "score-vs-noise.provenance.json"), "utf8"));
  check(`${f}: its index row has the date, short commit and machine of score-vs-noise.provenance.json`, row.includes(prov.date.slice(0, 10)) && row.includes("`" + prov.commit.slice(0, 7) + "`") && row.includes(prov.machine));
}

// ---- C. the score benchmark
const csvRaw = readFileSync(join(folder, "score-vs-noise.csv"));
const csvDoc = read("docs", "score-vs-noise.csv");
check("docs/benchmarks/score-vs-noise.csv is byte-identical to docs/score-vs-noise.csv", Buffer.compare(csvRaw, csvDoc) === 0);
const prov = JSON.parse(readFileSync(join(folder, "score-vs-noise.provenance.json"), "utf8"));
check("the provenance file holds the SHA-256 of the CSV", prov.data.csv_sha256 === sha(csvRaw));
check("the provenance file holds the SHA-256 of docs/score-vs-noise.svg", prov.data.svg_sha256 === sha(read("docs", "score-vs-noise.svg")));
check("the provenance file holds the CSV's row count", prov.data.rows === csvRaw.toString("utf8").trimEnd().split("\n").length - 1, `${prov.data.rows}`);
check("the provenance file says three fresh runs were byte-identical, bench --verify printed PASS, and keeps the three wall-clock times",
  prov.data.fresh_runs_byte_identical === true && prov.data.bench_verify === "PASS" && prov.data.bench_wall_clock_ms_runs.length === 3 && prov.data.bench_wall_clock_ms_best === Math.min(...prov.data.bench_wall_clock_ms_runs));
const corpusHash = sha(read("bench", "corpus", "clean.txt"));
for (const f of ["score-vs-noise.provenance.json", "joiner-sites.json", "gate-holds.json"]) {
  const j = JSON.parse(readFileSync(join(folder, f), "utf8"));
  check(`${f} names the SHA-256 of bench/corpus/clean.txt`, j.data.corpus === "bench/corpus/clean.txt" && j.data.corpus_sha256 === corpusHash);
}
const tp = JSON.parse(readFileSync(join(folder, "throughput-m5pro-48gb.json"), "utf8"));
check("throughput: five measurements, each with five runs, best_ms the fastest run rounded to a whole millisecond",
  tp.data.results.length === 5 && tp.data.results.every((r) => r.runs_ms.length === tp.data.runs_per_measurement && r.best_ms === Number(Math.min(...r.runs_ms).toFixed(0))));
check("throughput: the input is the 1 MiB text of the README (1,048,569 bytes, 12,888 lines, 273,779 clusters, no issue)", tp.data.input.bytes === 1048569 && tp.data.input.lines === 12888 && tp.data.input.clusters === 273779 && tp.data.input.issues === 0);

// ---- D. the CI run's sizes
const ciRaw = JSON.parse(readFileSync(join(folder, "ci-run-43667702791.json"), "utf8"));
const sizeOf = (job) => [...job.built_files.map((f) => f.bytes), ...(job.workflow_artifact ? [job.workflow_artifact.size_bytes] : [])];
const wheelJobs = ciRaw.data.jobs.filter((j) => j.job.startsWith("wheel and sdist"));
const otherJobs = ciRaw.data.jobs.filter((j) => !j.job.startsWith("wheel and sdist"));
const sizes = ciRaw.data.jobs.flatMap(sizeOf);
const tableSizes = wheelJobs.flatMap(sizeOf);
const rel = read("docs", "release.md").toString("utf8");
const sec = rel.slice(rel.indexOf("| Job (job id) | Built |"), rel.indexOf("What the run proved:"));
const inDoc = [...sec.matchAll(/(\d{1,3}(?:,\d{3})+) bytes/g)].map((m) => Number(m[1].replace(/,/g, "")));
check(`docs/release.md's CI table quotes exactly the ${tableSizes.length} sizes of the three wheel jobs in ci-run-43667702791.json`, JSON.stringify([...inDoc].sort((a, b) => a - b)) === JSON.stringify([...tableSizes].sort((a, b) => a - b)), `table has ${inDoc.join(", ")}`);
const proved = rel.slice(rel.indexOf("What the run proved:"), rel.indexOf("## Packaging notes"));
for (const v of otherJobs.flatMap(sizeOf)) check(`docs/release.md quotes the packaging job's ${v.toLocaleString("en-US")} bytes after the table`, proved.includes(`${v.toLocaleString("en-US")} bytes`));
for (const m of proved.matchAll(/(\d{1,3}(?:,\d{3})+) bytes/g)) {
  const v = Number(m[1].replace(/,/g, ""));
  const around = proved.slice(Math.max(0, m.index - 220), m.index + 220).toLowerCase();
  check(`docs/release.md: ${m[1]} bytes (after the CI table) is in the CI file or marked raw data not kept nearby`, sizes.includes(v) || around.includes("raw data not kept"), `${v}`);
}
check("the CI file is for run 43667702791 at 5ff0c47", ciRaw.data.run_id === 43667702791 && ciRaw.commit.startsWith("5ff0c47"));

process.stdout.write(JSON.stringify(out));
JS
RJ=$(node "${TMPDIR:-/tmp}/benchmarks-raw-$$.mjs" "$REPO" "$B" 2>&1)
RSTATUS=$?
if [ "$RSTATUS" -ne 0 ]; then
  fail "the raw files could be checked (node said: $(printf '%s' "$RJ" | head -4 | tr '\n' ' '))"
else
  NR=$(printf '%s' "$RJ" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(String(JSON.parse(s).length)))')
  for i in $(seq 0 $((NR - 1))); do
    LINE=$(printf '%s' "$RJ" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const [a,b]=JSON.parse(s)[Number(process.argv[1])];process.stdout.write(a+"\u001f"+b)})' "$i")
    IFS=$'\037' read -r STATE TEXT <<< "$LINE"
    case "$STATE" in ok) ok "$TEXT" ;; *) fail "$TEXT" ;; esac
  done
  if [ "$NR" -ge 100 ]; then ok "ran $NR checks on the raw files"; else fail "ran at least 100 checks on the raw files (ran $NR)"; fi
fi

echo "== E. the checks can fail"
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/benchmarks-raw-e.XXXXXX")
# a minimal copy of the repository: what the node check reads
mkdir -p "$SCRATCH/docs/benchmarks" "$SCRATCH/bench/corpus"
cp "$B"/* "$SCRATCH/docs/benchmarks/"
cp docs/score-vs-noise.csv docs/score-vs-noise.svg docs/release.md "$SCRATCH/docs/"
cp bench/corpus/clean.txt "$SCRATCH/bench/corpus/"
mutated() { # mutated <name> <sed expression on a copy of one file> <file>: runs the node check on the scratch copy and prints the number of failures
  cp "$B/$3" "$SCRATCH/docs/benchmarks/$3"
  sed -i.bak "$2" "$SCRATCH/docs/benchmarks/$3" && rm -f "$SCRATCH/docs/benchmarks/$3.bak"
  node "${TMPDIR:-/tmp}/benchmarks-raw-$$.mjs" "$SCRATCH" docs/benchmarks | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(String(JSON.parse(s).filter(x=>x[0]!=="ok").length)))'
  cp "$B/$3" "$SCRATCH/docs/benchmarks/$3"
}
BASE=$(node "${TMPDIR:-/tmp}/benchmarks-raw-$$.mjs" "$SCRATCH" docs/benchmarks | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(String(JSON.parse(s).filter(x=>x[0]!=="ok").length)))')
expect_eq "the unmodified scratch copy has no failing check" 0 "$BASE"
[ "$(mutated m1 's/"commit": "3c0bb4dcc0a53bb5d87c4971d1c6e1e30b109e39"/"commit": "3c0bb4d"/' throughput-m5pro-48gb.json)" -gt 0 ] && ok "a short commit is refused" || fail "a short commit is refused"
[ "$(mutated m2 's/"build_inputs_modified": false/"build_inputs_modified": true/' gate-holds.json)" -gt 0 ] && ok "a file measured on modified build inputs is refused" || fail "a file measured on modified build inputs is refused"
[ "$(mutated m3 's/"machine": "Apple M5 Pro, 48 GB"/"machine": "Apple M5 Pro"/' demo-1mib-m5pro-48gb.json)" -gt 0 ] && ok "a machine label without RAM is refused" || fail "a machine label without RAM is refused"
[ "$(mutated m4 's/"date": "[^"]*"/"date": "yesterday"/' joiner-sites.json)" -gt 0 ] && ok "a date that is not UTC to the second is refused" || fail "a date that is not UTC to the second is refused"
[ "$(mutated m5 's/"best_ms": 238/"best_ms": 237/' throughput-m5pro-48gb.json)" -gt 0 ] && ok "a best_ms that is not the fastest run is refused" || fail "a best_ms that is not the fastest run is refused"
[ "$(mutated m6 's/"bytes": 254335/"bytes": 254336/' ci-run-43667702791.json)" -gt 0 ] && ok "a CI size that docs/release.md does not quote is refused" || fail "a CI size that docs/release.md does not quote is refused"
[ "$(mutated m7 's/"method": "/"method": "run in \/Users\/someone\/work: /' wasm-linearity-m5pro-48gb.json)" -gt 0 ] && ok "a builder path in a file is refused" || fail "a builder path in a file is refused"
printf 'a\n' >> "$SCRATCH/docs/benchmarks/score-vs-noise.csv"
LAST=$(node "${TMPDIR:-/tmp}/benchmarks-raw-$$.mjs" "$SCRATCH" docs/benchmarks | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(String(JSON.parse(s).filter(x=>x[0]!=="ok").length)))')
[ "$LAST" -gt 0 ] && ok "a CSV copy that differs from docs/score-vs-noise.csv is refused" || fail "a CSV copy that differs from docs/score-vs-noise.csv is refused"
cp "$B/score-vs-noise.csv" "$SCRATCH/docs/benchmarks/score-vs-noise.csv"
cp "$B/ci-run-43667702791.json" "$SCRATCH/docs/benchmarks/ci-run-43667702791.json"
printf '{}\n' > "$SCRATCH/docs/benchmarks/extra.json"
EXTRA=$(node "${TMPDIR:-/tmp}/benchmarks-raw-$$.mjs" "$SCRATCH" docs/benchmarks | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(String(JSON.parse(s).filter(x=>x[0]!=="ok").length)))')
[ "$EXTRA" -gt 0 ] && ok "a raw file that the index does not list is refused" || fail "a raw file that the index does not list is refused"
# the scratch folder holds only copies made above; remove each file by name, then the folders (no recursive delete)
for f in "$SCRATCH"/docs/benchmarks/* "$SCRATCH"/docs/* "$SCRATCH"/bench/corpus/*; do [ -f "$f" ] && rm -f "$f"; done
rmdir "$SCRATCH/docs/benchmarks" "$SCRATCH/docs" "$SCRATCH/bench/corpus" "$SCRATCH/bench" "$SCRATCH" 2>/dev/null
finish
