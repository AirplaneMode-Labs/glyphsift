// Throughput of the validator on one text file: WASM validate(), score_ppm() and gate() in Node (best of 5) and the
// native `glyphsift check` and `glyphsift gate` (wall clock including process start, output to a pipe, 5 runs).
//
//   node scripts/throughput.mjs <text-file> [--cli target/release/glyphsift] [--json docs/benchmarks/<file>.json] [--machine "<model>, <N> GB"]
//
// Needs dist/wasm/nodejs (scripts/build-wasm.sh) and the release CLI (cargo build --release -p glyphsift-cli).
// Make the 1 MiB text the README benchmark uses with the one-line Node command in docs/release.md, row 2.
// Paths are resolved from this file's location and the arguments; nothing is hard-coded.
//
// --json writes the raw result file (owner decision, 20 Nov 2026: every benchmark is committed under docs/benchmarks/ with its date,
// commit, machine and method; see docs/benchmarks/README.md): the five runs of every measurement, not only the best, and the
// envelope of scripts/lib/bench-provenance.mjs. --machine names a machine Node cannot name ("<CPU model>, <N> GB" is the default).
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { basename, dirname, relative, resolve } from "node:path";
import { sha256File, writeRaw } from "./lib/bench-provenance.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const takeOpt = (name) => {
  const i = args.indexOf(name);
  return i === -1 ? undefined : args.splice(i, 2)[1];
};
const cliArg = takeOpt("--cli");
const jsonArg = takeOpt("--json");
const machine = takeOpt("--machine");
const cli = resolve(root, cliArg ?? `target/release/glyphsift${process.platform === "win32" ? ".exe" : ""}`);
if (args.length !== 1) {
  console.error('usage: node scripts/throughput.mjs <text-file> [--cli <glyphsift binary>] [--json <raw result file>] [--machine "<model>, <N> GB"]');
  process.exit(2);
}
const file = resolve(args[0]);
const g = createRequire(import.meta.url)(resolve(root, "dist/wasm/nodejs/glyphsift.js"));
const text = readFileSync(file, "utf8");
const bytes = Buffer.byteLength(text);
const report = JSON.parse(g.validate(text));
console.log(`input: ${bytes} bytes, ${report.lines.length} lines, ${report.summary.cluster_count} clusters, ${report.summary.issue_count} issues, score ${report.score.ppm}`);
const best = (fn, n = 5) => {
  const t = [];
  for (let i = 0; i < n; i++) {
    const a = process.hrtime.bigint();
    fn();
    t.push(Number(process.hrtime.bigint() - a) / 1e6);
  }
  return t;
};
const fmt = (t) => `${t.map((x) => x.toFixed(0)).join(", ")}; best ${Math.min(...t).toFixed(0)} ms`;
const results = [];
const measure = (id, what, t) => {
  results.push({ id, what, runs_ms: t.map((x) => Number(x.toFixed(3))), best_ms: Number(Math.min(...t).toFixed(0)) });
  return t;
};
console.log(`WASM validate() in Node, five runs ms: ${fmt(measure("wasm_validate", "WASM validate() in Node", best(() => g.validate(text))))}`);
console.log(`WASM score_ppm() in Node, five runs ms: ${fmt(measure("wasm_score_ppm", "WASM score_ppm() in Node", best(() => g.score_ppm(text))))}`);
console.log(`WASM gate() in Node, five runs ms: ${fmt(measure("wasm_gate", "WASM gate() in Node", best(() => g.gate(text))))} (verdict ${JSON.parse(g.gate(text)).verdict})`);
const n = best(() => execFileSync(cli, ["check", file], { maxBuffer: 1 << 30 }));
console.log(`native glyphsift check (wall clock incl. process start, output to a pipe), five runs ms: ${fmt(measure("native_check", "native glyphsift check", n))}`);
const ng = best(() => execFileSync(cli, ["gate", file], { maxBuffer: 1 << 30 }));
console.log(`native glyphsift gate (wall clock incl. process start, output to a pipe), five runs ms: ${fmt(measure("native_gate", "native glyphsift gate", ng))}`);

if (jsonArg !== undefined) {
  const shown = (p) => (relative(root, p).startsWith("..") ? basename(p) : relative(root, p).split("\\").join("/"));
  const doc = writeRaw(
    resolve(jsonArg),
    {
      benchmark: "throughput",
      method:
        "One text of about 1 MiB: the synthetic corpus bench/corpus/clean.txt repeated line by line until the next line would pass 1,048,576 bytes (the one-line Node command in docs/release.md, row 2). " +
        "Each measurement is five runs on that text; best_ms is the fastest of the five, rounded to a whole millisecond, and runs_ms keeps all five. " +
        "WASM: wall clock (process.hrtime) around one call of validate(), score_ppm() or gate() on the whole text in one Node process, from dist/wasm/nodejs; the first run is not discarded. " +
        "Native: wall clock of one run of the release binary on the file, process start included, output read through a pipe; the first run is not discarded and is not forced cold.",
      command: `node scripts/throughput.mjs ${basename(file)} --cli ${cliArg === undefined ? "target/release/glyphsift" : shown(cli)} --json ${shown(resolve(jsonArg))}`,
      data: {
        input: { name: basename(file), bytes, lines: report.lines.length, clusters: report.summary.cluster_count, issues: report.summary.issue_count, score_ppm: report.score.ppm, sha256: sha256File(file) },
        runs_per_measurement: 5,
        results,
      },
    },
    { machine, extraEnvironment: { glyphsift: execFileSync(cli, ["--version"], { encoding: "utf8" }).trim() } },
  );
  console.log(`wrote ${shown(resolve(jsonArg))} (machine: ${doc.machine}, commit ${doc.commit.slice(0, 7)})`);
}
