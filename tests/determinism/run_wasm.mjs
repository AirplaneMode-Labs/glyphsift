// WASM leg of the determinism gate: the report glyphsift.validate() returns in WASM must equal, byte
// for byte, the report the native CLI printed for the same sample (tests/determinism/expected/).
//
//   scripts/build-wasm.sh && node tests/determinism/run_wasm.mjs
//
// Exit 0 when every sample matches; 1 on the first mismatch, naming the sample.
import { createRequire } from "node:module";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const require = createRequire(import.meta.url);
const g = require(join(process.env.GLYPHSIFT_WASM_DIR ?? join(root, "dist", "wasm", "nodejs"), "glyphsift.js"));

const samples = join(root, "tests", "determinism", "samples");
const expected = join(root, "tests", "determinism", "expected");
const names = readdirSync(samples).filter((n) => n.endsWith(".txt")).sort();
if (names.length < 8) {
  console.error(`expected at least 8 samples, found ${names.length}`);
  process.exit(1);
}
let bad = 0;
for (const name of names) {
  const stem = name.slice(0, -".txt".length);
  // Read as bytes and decode as UTF-8 without a BOM strip: a BOM at offset 0 is part of the input.
  const text = new TextDecoder("utf-8", { ignoreBOM: true }).decode(readFileSync(join(samples, name)));
  const want = readFileSync(join(expected, `${stem}.json`), "utf8");
  const got = `${g.validate(text)}\n`;
  const ok = got === want;
  console.log(`${ok ? "ok  " : "FAIL"} ${stem}: wasm validate() ${ok ? "equals" : "DIFFERS FROM"} the native CLI report (${Buffer.byteLength(got)} bytes)`);
  if (!ok) bad += 1;
}
console.log(bad === 0 ? `wasm: ${names.length} samples byte-identical to native` : `wasm: ${bad} sample(s) differ`);
process.exit(bad === 0 ? 0 : 1);
