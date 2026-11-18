// WASM leg of the gate determinism check (Sprint 5, D3-01): gate() in the WASM build over the 200-case corpus in
// tests/determinism/gate must return, byte for byte, the line recorded in expected.jsonl. A case recorded as
// `rejected` must throw: a TypeError for a string that is not well-formed (an unpaired surrogate, checked with
// String.prototype.isWellFormed before the module is called, because wasm-bindgen would turn it into U+FFFD), and an
// Error for input over 4 MiB.
//
//   scripts/build-wasm.sh && node tests/determinism/run_gate_wasm.mjs
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadCases, loadExpected, textOf } from "./gate/corpus.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const require = createRequire(import.meta.url);
const g = require(join(process.env.GLYPHSIFT_WASM_DIR ?? join(root, "dist", "wasm", "nodejs"), "glyphsift.js"));

const cases = loadCases();
const expected = loadExpected();
let bad = 0;
let typeErrors = 0;
cases.forEach((c, n) => {
  const text = textOf(c);
  const want = expected[n];
  let got;
  let err;
  try {
    got = c.threshold_ppm === null ? g.gate(text) : g.gate(text, c.threshold_ppm);
  } catch (e) {
    err = e;
  }
  let ok;
  if (want === "rejected") {
    // An ill-formed string is a TypeError; the 4 MiB refusal is an Error whose message says "too large".
    const illFormed = !text.isWellFormed();
    ok = err instanceof Error && (illFormed ? err instanceof TypeError : /too large/.test(err.message));
    if (ok && illFormed) typeErrors += 1;
  } else {
    ok = err === undefined && got === want;
  }
  if (!ok) {
    bad += 1;
    console.log(`FAIL ${c.id} (${c.note}): ${err ? `threw ${err.constructor.name}: ${err.message}` : `got ${String(got).slice(0, 200)}`}; want ${want.slice(0, 200)}`);
  }
});
console.log(`${bad === 0 ? "ok  " : "FAIL"} wasm gate() matches expected.jsonl on all ${cases.length} cases`);
console.log(`${typeErrors === 6 ? "ok  " : "FAIL"} the six ill-formed strings are rejected with a TypeError (${typeErrors})`);
if (typeErrors !== 6) bad += 1;
console.log(bad === 0 ? "gate wasm: 200 cases match" : "gate wasm: FAILED");
process.exit(bad === 0 ? 0 : 1);
