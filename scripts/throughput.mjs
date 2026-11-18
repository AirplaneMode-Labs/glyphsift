// Throughput of the validator on one text file: WASM validate(), score_ppm() and gate() in Node (best of 5) and the
// native `glyphsift check` and `glyphsift gate` (wall clock including process start, output to a pipe, 5 runs).
//
//   node scripts/throughput.mjs <text-file> [--cli target/release/glyphsift]
//
// Needs dist/wasm/nodejs (scripts/build-wasm.sh) and the release CLI (cargo build --release -p glyphsift-cli).
// Make the 1 MiB text the README benchmark uses with the one-line Node command in docs/release.md, row 2.
// Paths are resolved from this file's location and the arguments; nothing is hard-coded.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const ci = args.indexOf("--cli");
let cli = resolve(root, `target/release/glyphsift${process.platform === "win32" ? ".exe" : ""}`);
if (ci !== -1) cli = resolve(args.splice(ci, 2)[1]);
if (args.length !== 1) {
  console.error("usage: node scripts/throughput.mjs <text-file> [--cli <glyphsift binary>]");
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
console.log(`WASM validate() in Node, five runs ms: ${fmt(best(() => g.validate(text)))}`);
console.log(`WASM score_ppm() in Node, five runs ms: ${fmt(best(() => g.score_ppm(text)))}`);
console.log(`WASM gate() in Node, five runs ms: ${fmt(best(() => g.gate(text)))} (verdict ${JSON.parse(g.gate(text)).verdict})`);
const n = best(() => execFileSync(cli, ["check", file], { maxBuffer: 1 << 30 }));
console.log(`native glyphsift check (wall clock incl. process start, output to a pipe), five runs ms: ${fmt(n)}`);
const ng = best(() => execFileSync(cli, ["gate", file], { maxBuffer: 1 << 30 }));
console.log(`native glyphsift gate (wall clock incl. process start, output to a pipe), five runs ms: ${fmt(ng)}`);
