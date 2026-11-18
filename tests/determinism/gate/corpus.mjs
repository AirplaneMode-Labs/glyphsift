// Shared loader for the gate corpus (tests/determinism/gate/cases.jsonl and expected.jsonl, written by
// scripts/make-gate-corpus.mjs). Used by the native, Python-adjacent and WASM runners and by the generator.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const gateDir = dirname(fileURLToPath(import.meta.url));

/** The text of a case: `text`, or each [string, count] part repeated and joined. */
export function textOf(c) {
  return "parts" in c ? c.parts.map(([s, k]) => s.repeat(k)).join("") : c.text;
}

export function loadCases() {
  return readFileSync(join(gateDir, "cases.jsonl"), "utf8")
    .split("\n")
    .filter((l) => l !== "")
    .map((l) => JSON.parse(l));
}

/** One entry per case: the canonical gate JSON, or the word `rejected`. */
export function loadExpected() {
  return readFileSync(join(gateDir, "expected.jsonl"), "utf8")
    .split("\n")
    .filter((l) => l !== "");
}

/** UTF-8 bytes of a JS string; a lone surrogate becomes WTF-8 (ED A0..BF xx), which is not valid UTF-8. */
export function wtf8(text) {
  const out = [];
  for (let i = 0; i < text.length; i += 1) {
    let cp = text.charCodeAt(i);
    if (cp >= 0xd800 && cp <= 0xdbff && i + 1 < text.length) {
      const lo = text.charCodeAt(i + 1);
      if (lo >= 0xdc00 && lo <= 0xdfff) {
        cp = 0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00);
        i += 1;
      }
    }
    if (cp < 0x80) out.push(cp);
    else if (cp < 0x800) out.push(0xc0 | (cp >> 6), 0x80 | (cp & 63));
    else if (cp < 0x10000) out.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
    else out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 63), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
  }
  return Buffer.from(out);
}

/** How many expected lines carry each verdict, and how many are `rejected`. */
export function tally(expected) {
  const t = { pass: 0, hold: 0, not_scored: 0, rejected: 0 };
  for (const e of expected) t[e === "rejected" ? "rejected" : JSON.parse(e).verdict] += 1;
  return t;
}
