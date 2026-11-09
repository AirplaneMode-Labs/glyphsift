// WASM safety check for the glyphsift validator, run in node against the nodejs-target build.
//
//   scripts/build-wasm.sh && node tests/wasm/run_wasm_safety.mjs
//
// It fails (exit 1) on any trap, panic or wrong answer. Checks:
//   1. the export list is exactly validate, score_ppm, report_spec, clusters, clusters_json and
//      issue_kinds (the JS module and the raw .wasm exports);
//   2. the 20,000-string fuzz set of crates/glyphsift-core/tests/fuzz.rs (xorshift64* seed 1 over
//      U+0000..U+097F, ZWJ, ZWNJ and 16 private-use code points): no trap, and the FNV-1a hash of
//      all 20,000 canonical reports equals the constant the native test asserts, so WASM and
//      native agree byte for byte on every one of them;
//   3. a 1 MiB input of clean text, and a 1 MiB single-cluster run of matras, validate without a
//      trap; input over the 4 MiB core limit is refused with a "too large" error, not a trap;
//   4. a 5,000-mark run is timed against a 2,500-mark run: the ratio is logged and must be below 3
//      (linear is 2, quadratic is 4).
//
// The nodejs-target build is CommonJS; this script loads it with createRequire.

import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const require = createRequire(import.meta.url);
const pkgDir = process.env.GLYPHSIFT_WASM_DIR ?? join(root, "dist", "wasm", "nodejs");

// Keep in step with FUZZ_HASH in crates/glyphsift-core/tests/fuzz.rs.
const FUZZ_HASH = 0x3406f55bff039ed3n;
const EXPECTED_EXPORTS = ["clusters", "clusters_json", "issue_kinds", "report_spec", "score_ppm", "validate"];
const MAX_INPUT_BYTES = 4 * 1024 * 1024;

let failures = 0;
function check(ok, what) {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) failures += 1;
}
function stage(name, fn) {
  try {
    fn();
  } catch (err) {
    check(false, `${name}: threw ${err instanceof Error ? err.message : String(err)}`);
  }
}

const g = require(join(pkgDir, "glyphsift.js"));

// ---- 1. the export list ------------------------------------------------------------------------
stage("exports", () => {
  const js = Object.keys(g)
    .filter((k) => typeof g[k] === "function" && !k.startsWith("__") && k !== "initSync" && k !== "default")
    .sort();
  check(JSON.stringify(js) === JSON.stringify(EXPECTED_EXPORTS), `JS exports are exactly ${EXPECTED_EXPORTS.join(", ")} (found ${js.join(", ")})`);
  const bytes = readFileSync(join(pkgDir, "glyphsift_bg.wasm"));
  const raw = WebAssembly.Module.exports(new WebAssembly.Module(bytes))
    .map((e) => e.name)
    .filter((n) => !n.startsWith("__"))
    .sort();
  const want = [...EXPECTED_EXPORTS, "memory"].sort();
  check(JSON.stringify(raw) === JSON.stringify(want), `raw wasm exports are exactly ${want.join(", ")} (found ${raw.join(", ")})`);
  check(g.report_spec() === "glyphsift.report/0.2", `report_spec() is glyphsift.report/0.2 (got ${g.report_spec()})`);
  check(JSON.parse(g.issue_kinds()).length === 16, "issue_kinds() lists 16 rules");
});

// ---- 2. the fuzz set ---------------------------------------------------------------------------
const MASK = (1n << 64n) - 1n;
function xorshift64star(seed) {
  let x = BigInt(seed) & MASK;
  return () => {
    x ^= x >> 12n;
    x ^= (x << 25n) & MASK;
    x ^= x >> 27n;
    return (x * 0x2545f4914f6cdd1dn) & MASK;
  };
}
const ALPHABET = 0x980n + 2n + 16n;
function alphabetChar(i) {
  const n = Number(i);
  if (n < 0x980) return String.fromCodePoint(n);
  if (n === 0x980) return "\u{200D}";
  if (n === 0x981) return "\u{200C}";
  return String.fromCodePoint(0xf0d0 + (n - 0x982));
}
function fuzzStrings() {
  const next = xorshift64star(1);
  const out = [];
  for (let n = 0; n < 20000; n += 1) {
    const len = Number(next() % 25n);
    let s = "";
    for (let k = 0; k < len; k += 1) s += alphabetChar(next() % ALPHABET);
    out.push(s);
  }
  return out;
}
// FNV-1a 64 over bytes, as two 32-bit halves (a BigInt per byte would take minutes).
function fnv1a64(state, bytes) {
  let [hi, lo] = state;
  for (let i = 0; i < bytes.length; i += 1) {
    lo ^= bytes[i];
    // multiply by 0x100000001b3 = 2^40 + 0x1b3 modulo 2^64
    const t = (lo >>> 0) * 0x1b3;
    const newLo = t % 4294967296;
    const carry = Math.floor(t / 4294967296);
    const newHi = ((hi >>> 0) * 0x1b3 + carry + (((lo >>> 0) & 0xffffff) * 256)) % 4294967296;
    lo = newLo;
    hi = newHi;
  }
  return [hi >>> 0, lo >>> 0];
}
stage("fuzz", () => {
  const enc = new TextEncoder();
  let state = [0xcbf29ce4, 0x84222325];
  const nl = Uint8Array.of(10);
  let reports = 0;
  for (const s of fuzzStrings()) {
    const json = g.validate(s); // a trap or a thrown error ends the stage
    state = fnv1a64(state, enc.encode(json));
    state = fnv1a64(state, nl);
    reports += 1;
  }
  const hash = (BigInt(state[0]) << 32n) | BigInt(state[1]);
  check(reports === 20000, "validate() returned a report for all 20,000 fuzz strings (no trap)");
  check(hash === FUZZ_HASH, `fuzz hash 0x${hash.toString(16).padStart(16, "0")} equals the native 0x${FUZZ_HASH.toString(16)}`);
});

// ---- 3. large inputs ---------------------------------------------------------------------------
stage("1 MiB clean text", () => {
  const unit = "नमस्ते दुनिया।\n";
  const text = unit.repeat(Math.ceil((1 << 20) / Buffer.byteLength(unit)));
  check(Buffer.byteLength(text) >= 1 << 20, `input is ${Buffer.byteLength(text)} bytes (at least 1 MiB)`);
  const t0 = performance.now();
  const r = JSON.parse(g.validate(text));
  const ms = performance.now() - t0;
  check(r.issues.length === 0 && r.score.ppm === 1000000, "a 1 MiB clean text has no issues and scores 1000000");
  console.log(`     1 MiB clean text: ${r.summary.cluster_count} clusters, ${ms.toFixed(0)} ms`);
  check(g.score_ppm(text) === 1000000, "score_ppm() agrees on the 1 MiB text");
});
stage("1 MiB single-cluster run", () => {
  const text = "क" + "ा".repeat(Math.floor(((1 << 20) - 3) / 3));
  check(Buffer.byteLength(text) <= 1 << 20 && Buffer.byteLength(text) > (1 << 20) - 6, `input is ${Buffer.byteLength(text)} bytes`);
  const t0 = performance.now();
  const r = JSON.parse(g.validate(text));
  const ms = performance.now() - t0;
  check(r.summary.cluster_count === 1 && r.summary.issue_count === r.code_points - 2, "one cluster with every extra matra reported as double_matra");
  console.log(`     1 MiB matra run: ${r.summary.issue_count} issues, ${ms.toFixed(0)} ms`);
});
stage("over the limit", () => {
  const big = "क".repeat(Math.floor(MAX_INPUT_BYTES / 3) + 1);
  let message = "";
  try {
    g.validate(big);
    check(false, "an input over 4 MiB must be refused");
  } catch (err) {
    message = err instanceof Error ? err.message : String(err);
  }
  check(message.includes("too large"), `an input over 4 MiB throws a 'too large' error, not a trap (${message})`);
  // The module is still usable after the refusal.
  check(g.score_ppm("नमस्ते") === 1000000, "the module still works after refusing an input");
});

stage("clusters over the limit (S1-051)", () => {
  const refuse = (fn, name, text, label) => {
    let message = "";
    try {
      fn(text);
      check(false, `${name}(${label}) must be refused`);
      return;
    } catch (err) {
      message = err instanceof Error ? err.message : String(err);
    }
    check(message.includes("too large"), `${name}(${label}) throws a 'too large' error, not a trap (${message})`);
  };
  const justOver = "a".repeat(MAX_INPUT_BYTES + 1);
  const eightMiB = "a".repeat(8 * 1024 * 1024);
  for (const [name, fn] of [["clusters", g.clusters], ["clusters_json", g.clusters_json]]) {
    refuse(fn, name, justOver, "4 MiB + 1");
    refuse(fn, name, eightMiB, "8 MiB");
  }
  check(JSON.parse(g.clusters("नमस्ते")).length === 3, "clusters() still works after the refusals");
  check(JSON.parse(g.clusters_json("क")).length === 1, "clusters_json() still works after the refusals");
});

// ---- 4. linearity ------------------------------------------------------------------------------
stage("linear in the number of marks", () => {
  const run = (n) => "क" + "ा".repeat(n);
  const best = (text) => {
    let min = Infinity;
    for (let round = 0; round < 7; round += 1) {
      const t0 = performance.now();
      for (let i = 0; i < 20; i += 1) g.validate(text);
      min = Math.min(min, performance.now() - t0);
    }
    return min;
  };
  const small = run(2500);
  const big = run(5000);
  best(small); // warm up
  const t2500 = best(small);
  const t5000 = best(big);
  const ratio = t5000 / t2500;
  console.log(`     2,500 marks: ${(t2500 / 20).toFixed(3)} ms per call; 5,000 marks: ${(t5000 / 20).toFixed(3)} ms per call; ratio ${ratio.toFixed(2)} (linear is 2.00, quadratic 4.00)`);
  check(ratio < 3, `the 5,000-mark run takes less than 3x the 2,500-mark run (ratio ${ratio.toFixed(2)})`);
  const r = JSON.parse(g.validate(big));
  check(r.summary.issue_count === 4999 && r.summary.cluster_count === 1, "the 5,000-mark run reports 4,999 double_matra issues in one cluster");
});

console.log(failures === 0 ? "wasm safety: all checks passed" : `wasm safety: ${failures} check(s) FAILED`);
process.exit(failures === 0 ? 0 : 1);
