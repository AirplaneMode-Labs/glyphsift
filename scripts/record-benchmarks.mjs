// Records the deterministic benchmarks as raw files under docs/benchmarks/ (owner decision, 20 Nov 2026).
//
//   node scripts/record-benchmarks.mjs score-vs-noise [--cli target/release/glyphsift] [--machine "<model>, <N> GB"]
//   node scripts/record-benchmarks.mjs joiner-sites   [--cli target/release/glyphsift] [--machine ...]
//   node scripts/record-benchmarks.mjs gate-holds                                      [--machine ...]
//
// score-vs-noise  runs `glyphsift bench` three times into a scratch folder, requires the CSV and the SVG to be byte-identical to
//                 the committed docs/score-vs-noise.{csv,svg} on every run, runs `bench --verify`, copies the CSV to
//                 docs/benchmarks/score-vs-noise.csv and writes docs/benchmarks/score-vs-noise.provenance.json (the SHA-256 of
//                 both files, the row count, the corpus hash and the three wall-clock times of the bench command).
// joiner-sites    runs `glyphsift corrupt --family joiner_inject --p 0.05 --seed N --sites <file>` for seeds 1 to 3 and counts the
//                 injected sites and the sites that declare an expected rule (docs/benchmarks/joiner-sites.json).
// gate-holds      runs the cargo test that prints the hold counts docs/gate.md quotes (and fails if the doc differs from them) and
//                 writes them as docs/benchmarks/gate-holds.json.
//
// The timing benchmarks have their own commands: scripts/throughput.mjs --json, tests/wasm/run_wasm_safety.mjs --bench-json and
// tests/demo/check_demo.mjs --bench-json. docs/benchmarks/README.md lists every command. Nothing here needs the network.
import { execFileSync, spawnSync } from "node:child_process";
import { copyFileSync, mkdtempSync, readFileSync, rmdirSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, relative, resolve } from "node:path";
import { root, sha256File, writeRaw } from "./lib/bench-provenance.mjs";

const args = process.argv.slice(2);
const takeOpt = (name) => {
  const i = args.indexOf(name);
  return i === -1 ? undefined : args.splice(i, 2)[1];
};
const cliArg = takeOpt("--cli");
const machine = takeOpt("--machine");
const [which, ...rest] = args;
if (!["score-vs-noise", "joiner-sites", "gate-holds"].includes(which) || rest.length) {
  console.error("usage: node scripts/record-benchmarks.mjs score-vs-noise|joiner-sites|gate-holds [--cli <glyphsift binary>] [--machine <label>]");
  process.exit(2);
}
const cli = resolve(root, cliArg ?? `target/release/glyphsift${process.platform === "win32" ? ".exe" : ""}`);
const cliShown = cliArg === undefined ? "target/release/glyphsift" : relative(root, cli).startsWith("..") ? basename(cli) : relative(root, cli).split("\\").join("/");
const out = (name) => join(root, "docs", "benchmarks", name);
const CORPUS = "bench/corpus/clean.txt";
const P_LABELS = ["0", "0.01", "0.02", "0.05", "0.1", "0.2", "0.4"];

const cliVersion = () => execFileSync(cli, ["--version"], { encoding: "utf8" }).trim();
const scratch = () => mkdtempSync(join(tmpdir(), "glyphsift-record-"));
const dispose = (dir, files) => {
  for (const f of files) {
    try {
      unlinkSync(join(dir, f));
    } catch {
      /* already gone */
    }
  }
  rmdirSync(dir);
};

if (which === "score-vs-noise") {
  const dir = scratch();
  const csvCommitted = join(root, "docs", "score-vs-noise.csv");
  const svgCommitted = join(root, "docs", "score-vs-noise.svg");
  const runs = [];
  for (let i = 0; i < 3; i++) {
    const t0 = process.hrtime.bigint();
    execFileSync(cli, ["bench", "--corpus", CORPUS, "--seeds", "1,2,3", "--csv", join(dir, "run.csv"), "--svg", join(dir, "run.svg")], { cwd: root, stdio: "pipe" });
    runs.push(Math.round(Number(process.hrtime.bigint() - t0) / 1e6));
    for (const [a, b] of [[join(dir, "run.csv"), csvCommitted], [join(dir, "run.svg"), svgCommitted]]) {
      if (sha256File(a) !== sha256File(b)) {
        console.error(`error: a fresh \`glyphsift bench\` run is not byte-identical to ${relative(root, b)}; regenerate the committed files first`);
        process.exit(1);
      }
    }
  }
  dispose(dir, ["run.csv", "run.svg"]);
  const verify = execFileSync(cli, ["bench", "--verify", "docs/score-vs-noise.csv"], { cwd: root, encoding: "utf8" });
  const verdict = /verdict: (\w+)/.exec(verify)?.[1];
  if (verdict !== "PASS") {
    console.error(`error: bench --verify did not print "verdict: PASS" (got ${verdict})`);
    process.exit(1);
  }
  copyFileSync(csvCommitted, out("score-vs-noise.csv"));
  const csv = readFileSync(csvCommitted, "utf8").trimEnd().split("\n");
  const header = csv.shift();
  const col = header.split(",");
  const rows = csv.map((l) => l.split(","));
  const uniq = (name) => [...new Set(rows.map((r) => r[col.indexOf(name)]))];
  writeRaw(
    out("score-vs-noise.provenance.json"),
    {
      benchmark: "score-vs-noise",
      method:
        "The 288-line synthetic corpus bench/corpus/clean.txt is corrupted by each of the 19 noise families and by `mixed` at 7 noise levels with seeds 1 to 3, and every result is scored. " +
        "The output is deterministic integers, so every run gives the same bytes: this file records that three fresh runs of the command below were byte-identical to the committed docs/score-vs-noise.csv and .svg, " +
        "that `glyphsift bench --verify` printed `verdict: PASS` for it, and the wall-clock time of each run (process start included). " +
        "The raw result is docs/benchmarks/score-vs-noise.csv, a byte-identical copy of docs/score-vs-noise.csv (which the tests, the chart and the source package read).",
      command: `${cliShown} bench --corpus ${CORPUS} --seeds 1,2,3 --csv docs/score-vs-noise.csv --svg docs/score-vs-noise.svg`,
      data: {
        raw_file: "docs/benchmarks/score-vs-noise.csv",
        rows: rows.length,
        csv_sha256: sha256File(csvCommitted),
        svg_sha256: sha256File(svgCommitted),
        corpus: CORPUS,
        corpus_sha256: sha256File(join(root, CORPUS)),
        families: uniq("family").length,
        p_levels: uniq("p"),
        seeds: uniq("seed").map(Number),
        fresh_runs_byte_identical: true,
        bench_verify: verdict,
        bench_wall_clock_ms_runs: runs,
        bench_wall_clock_ms_best: Math.min(...runs),
      },
    },
    { machine, extraEnvironment: { glyphsift: cliVersion() } },
  );
  console.log(`wrote docs/benchmarks/score-vs-noise.csv and score-vs-noise.provenance.json (${rows.length} rows; bench runs ${runs.join(", ")} ms)`);
}

if (which === "joiner-sites") {
  const dir = scratch();
  const seeds = {};
  for (const seed of [1, 2, 3]) {
    const file = join(dir, `sites-${seed}.json`);
    execFileSync(cli, ["corrupt", "--family", "joiner_inject", "--p", "0.05", "--seed", String(seed), "--sites", file], { cwd: root, input: readFileSync(join(root, CORPUS)), stdio: ["pipe", "ignore", "pipe"] });
    const j = JSON.parse(readFileSync(file, "utf8"));
    seeds[seed] = { sites: j.sites.length, declared_sites: j.sites.filter((s) => s.kinds.length > 0).length };
  }
  dispose(dir, [1, 2, 3].map((s) => `sites-${s}.json`));
  const total = (k) => Object.values(seeds).reduce((a, s) => a + s[k], 0);
  writeRaw(
    out("joiner-sites.json"),
    {
      benchmark: "joiner-sites",
      method:
        "`glyphsift corrupt --sites` lists every site the generator damaged. For the joiner_inject family at p=0.05 and seeds 1 to 3 on bench/corpus/clean.txt this counts the sites, and the sites that declare an expected rule " +
        "(a joiner that lands in a Devanagari-based cluster, where the zwj_zwnj_misplaced rule is expected to fire; one that lands after a space or other non-Devanagari cluster declares none and costs nothing). " +
        "The README quotes the totals: 599 of 807. The flagged_clusters column of docs/benchmarks/score-vs-noise.csv for the same rows (187, 205, 207) sums to the declared total.",
      command: `${cliShown} corrupt --family joiner_inject --p 0.05 --seed <1|2|3> --sites <file> < ${CORPUS} > /dev/null`,
      data: { family: "joiner_inject", p: "0.05", corpus: CORPUS, corpus_sha256: sha256File(join(root, CORPUS)), seeds, total_sites: total("sites"), total_declared_sites: total("declared_sites") },
    },
    { machine, extraEnvironment: { glyphsift: cliVersion() } },
  );
  console.log(`wrote docs/benchmarks/joiner-sites.json (${total("declared_sites")} of ${total("sites")})`);
}

if (which === "gate-holds") {
  const cmd = ["test", "--locked", "-p", "glyphsift-core", "--features", "corrupt", "--test", "gate_noise", "the_doc_tables_are_these_exact_hold_counts", "--", "--nocapture"];
  const r = spawnSync("cargo", cmd, { cwd: root, encoding: "utf8", maxBuffer: 1 << 26 });
  if (r.status !== 0 || !/test result: ok\. 1 passed/.test(r.stdout)) {
    console.error(`error: cargo ${cmd.join(" ")} failed (status ${r.status}); docs/gate.md and the generator disagree\n${r.stdout}\n${r.stderr}`);
    process.exit(1);
  }
  const rows = [];
  for (const line of r.stdout.split("\n")) {
    const m = /^\| (.+?) \| ((?:\d+ \| ){6}\d+) \|$/.exec(line);
    if (!m) continue;
    const label = m[1];
    const hold = m[2].split(" | ").map(Number);
    const fam = /^`(\w+)`$/.exec(label);
    const size = /^(\d+) lines? \((\d+) chunks\)$/.exec(label);
    if (fam) rows.push({ table: "by_family", family: fam[1], lines_per_chunk: 3, chunks: 288, hold });
    else if (size) rows.push({ table: "by_chunk_size", family: "mixed", lines_per_chunk: Number(size[1]), chunks: Number(size[2]), hold });
    else throw new Error(`unrecognised row label ${label}`);
  }
  if (rows.length !== 8) {
    console.error(`error: expected 8 rows (five families at three lines, mixed at one, three and eight lines), found ${rows.length}`);
    process.exit(1);
  }
  writeRaw(
    out("gate-holds.json"),
    {
      benchmark: "gate-holds",
      method:
        "The clean corpus bench/corpus/clean.txt is corrupted as the score benchmark does (the whole text at once, seeds 1 to 3), split back into lines, and cut into chunks of 1, 3 or 8 consecutive lines; every chunk goes through gate() " +
        "with the default threshold (975000 ppm). `hold` is the number of held chunks over the three seeds at each noise level; `chunks` is the number of chunks over the three seeds. " +
        "The rows are the ones the cargo test prints, and that test fails unless docs/gate.md holds exactly those rows: table `by_family` is the first table of docs/gate.md (five families, chunks of three lines), " +
        "`by_chunk_size` the second (the mixed family at one, three and eight lines per chunk).",
      command: "cargo test --locked -p glyphsift-core --features corrupt --test gate_noise the_doc_tables_are_these_exact_hold_counts -- --nocapture",
      data: { corpus: CORPUS, corpus_sha256: sha256File(join(root, CORPUS)), threshold_ppm: 975000, seeds: [1, 2, 3], p_levels: P_LABELS, rows },
    },
    { machine },
  );
  console.log(`wrote docs/benchmarks/gate-holds.json (${rows.length} rows)`);
}
