// Native leg of the gate determinism check (Sprint 5, D3-01): `glyphsift gate` over the 200-case corpus in
// tests/determinism/gate must print, byte for byte, the line recorded in expected.jsonl; a case recorded as
// `rejected` (an ill-formed string handed over as WTF-8, or input over 4 MiB) must exit 1 or 2 and print nothing.
//
//   cargo build --release -p glyphsift-cli && node tests/determinism/run_gate_native.mjs [--cli target/release/glyphsift]   (default: ${CARGO_TARGET_DIR:-target}/release/glyphsift)
//
// A CLI that cannot be run exits 1 with `cannot run <cli path>: <error message>` (tests/scripts/gate-native-error.sh).
// Also asserts what the corpus is for: exactly 200 cases, and every outcome (pass, hold, not_scored, rejected) is
// well represented, so a corpus that quietly stopped exercising the gate would fail here.
import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadCases, loadExpected, tally, textOf, wtf8 } from "./gate/corpus.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const i = process.argv.indexOf("--cli");
// BUG-T2-S5-14: without --cli the binary is looked for in ${CARGO_TARGET_DIR:-target}/release, as cargo wrote it (a relative
// CARGO_TARGET_DIR is relative to the repository root, where the scripts run cargo).
const targetDir = process.env.CARGO_TARGET_DIR || "target";
const cli = resolve(root, i >= 0 ? process.argv[i + 1] : join(targetDir, "release", `glyphsift${process.platform === "win32" ? ".exe" : ""}`));
console.log(`cli: ${cli}`);

const cases = loadCases();
const expected = loadExpected();
let bad = 0;
const check = (ok, what) => {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) bad += 1;
};
check(cases.length === 200 && expected.length === 200, `the corpus has 200 cases and 200 expected lines (${cases.length}, ${expected.length})`);
const t = tally(expected);
check(t.pass >= 40 && t.hold >= 40 && t.not_scored >= 20 && t.rejected === 7, `every outcome is represented: ${JSON.stringify(t)}`);

let differ = 0;
cases.forEach((c, n) => {
  const args = ["gate", ...(c.threshold_ppm === null ? [] : ["--threshold-ppm", String(c.threshold_ppm)]), "-"];
  const r = spawnSync(cli, args, { input: wtf8(textOf(c)), maxBuffer: 1 << 28 });
  // BUG-T2-S5-14: a CLI that cannot be run (missing binary, CARGO_TARGET_DIR elsewhere) has r.error set and r.stdout null.
  if (r.error || r.stdout === null || r.stdout === undefined) {
    console.error(`cannot run ${cli}: ${r.error ? r.error.message : "no output was captured"}`);
    process.exit(1);
  }
  const want = expected[n];
  let ok;
  if (want === "rejected") ok = (r.status === 1 || r.status === 2) && r.stdout.length === 0;
  else ok = r.status === 0 && r.stdout.toString("utf8") === `${want}\n`;
  if (!ok) {
    differ += 1;
    console.log(`FAIL ${c.id} (${c.note}): exit ${r.status}, stdout ${JSON.stringify(r.stdout.toString("utf8").slice(0, 200))}, stderr ${JSON.stringify(r.stderr.toString("utf8").slice(0, 200))}; want ${want.slice(0, 200)}`);
  }
});
check(differ === 0, `native \`glyphsift gate\` matches expected.jsonl on all ${cases.length} cases`);
console.log(bad === 0 ? "gate native: 200 cases match" : "gate native: FAILED");
process.exit(bad === 0 ? 0 : 1);
