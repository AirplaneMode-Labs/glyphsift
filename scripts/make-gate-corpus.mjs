#!/usr/bin/env node
// The 200-case synthetic corpus for the gate call (Sprint 5, D3-01, TD-42).
//
//   node scripts/make-gate-corpus.mjs --write [--cli target/release/glyphsift]
//   node scripts/make-gate-corpus.mjs --check
//
// --write regenerates tests/determinism/gate/cases.jsonl (this script is its only source) and then
// tests/determinism/gate/expected.jsonl from the native CLI (`glyphsift gate`), the way the report samples'
// expected files were made. --check regenerates the cases in memory and fails if the committed file differs, so the
// corpus cannot drift from this generator, and checks that expected.jsonl has one line per case.
//
// Every case is synthetic: the thirteen determinism samples, hand-written boundary cases, and seeded mixtures and
// mutations of the invented sentences in bench/corpus/clean.txt. No real document is used. The file is plain ASCII
// (every non-ASCII code unit is a \uXXXX escape) so that git and editors cannot normalise it, and a lone surrogate,
// which no UTF-8 file can hold, is written as its escape. A case is one of
//   {"id", "text", "threshold_ppm", "note"}              the text is the JSON string
//   {"id", "parts": [[string, count], ...], ...}         the text is each string repeated count times, in order
// and `expected.jsonl` has, per line, the canonical gate JSON or the word `rejected` (an ill-formed string, or input over
// 4 MiB: the bindings must all refuse it, each in its own way: WASM throws a TypeError for the first and an Error for the
// second, Python a ValueError, the CLI exit 2 for invalid UTF-8 and exit 1 for oversize).
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { tally, textOf, wtf8 } from "../tests/determinism/gate/corpus.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dir = join(root, "tests", "determinism", "gate");
const TOTAL = 200;

// xorshift64* (Vigna 2014), the lane's generator, over BigInt so the sequence is exact.
const MASK = (1n << 64n) - 1n;
function rng(seed) {
  let x = BigInt(seed) & MASK;
  return () => {
    x ^= x >> 12n;
    x ^= (x << 25n) & MASK;
    x ^= x >> 27n;
    return Number(((x * 0x2545f4914f6cdd1dn) & MASK) >> 11n); // 53 bits
  };
}

// JSON with every non-ASCII code unit escaped. JSON.stringify already escapes lone surrogates.
const esc = (value) => JSON.stringify(value).replace(/[\u007f-￿]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`);

function build() {
  const cases = [];
  const add = (c) => cases.push({ threshold_ppm: null, ...c });

  // A. the thirteen determinism samples, exactly as the report determinism gate reads them.
  const samplesDir = join(root, "tests", "determinism", "samples");
  for (const name of readdirSync(samplesDir).filter((n) => n.endsWith(".txt")).sort()) {
    const text = new TextDecoder("utf-8", { ignoreBOM: true }).decode(readFileSync(join(samplesDir, name)));
    add({ id: `g${String(cases.length + 1).padStart(3, "0")}`, note: `determinism sample ${name.slice(0, -4)}`, text });
  }

  // B. hand-written cases.
  const KA = "क";
  const hand = [
    ["empty", ""],
    ["one space", " "],
    ["newlines only", "\n\r\n"],
    ["ASCII digits", "0123456789"],
    ["punctuation", "?!.,;:-"],
    ["Latin sentence", "The quick brown fox jumps over the lazy dog."],
    ["Cyrillic", "Привет мир"],
    ["Tamil", "தமிழ்"],
    ["Bengali", "বাংলা"],
    ["CJK", "日本語のテキスト"],
    ["emoji only", "\u{1f600}\u{1f468}‍\u{1f469}"],
    ["ZWJ only", "‍"],
    ["replacement character only", "�"],
    ["BOM only", "﻿"],
    ["clean Hindi", "नमस्ते।"],
    ["clean Hindi sentence", "भारत एक विशाल देश है।"],
    ["clean Marathi", "मी मराठी बोलतो।"],
    ["Devanagari digits", "१२३"],
    ["danda only", "।"],
    ["conjunct", "क्षत्रिय"],
    ["Devanagari Extended", "꣠꣡ꣿ"],
    ["Vedic Extensions", "᳐᳑᳿"],
    ["one broken cluster of four", "कखग�"],
    ["matra with no base", "ि"],
    ["double matra", "काि"],
    ["virama alone", "्"],
    ["dead consonant at the end", "क्"],
    ["stray nukta", "़क"],
    ["control character in Hindi", "नमस\u0001ते"],
    ["tag characters after a letter", `${KA}\u{e0041}\u{e0042}`],
    ["foreign mark on Devanagari", `${KA}́`],
    ["half Devanagari, half Latin (500000 ppm)", `${KA} a`],
    ["a third Devanagari (333333 ppm)", `${KA} aa`],
    ["two thirds Devanagari (666666 ppm)", `${KA}ख a`],
    ["Latin with one Devanagari word", "hello world नमस्ते"],
    ["CRLF Hindi", "क\r\nख\r\n"],
  ];
  for (const [note, text] of hand) add({ id: `g${String(cases.length + 1).padStart(3, "0")}`, note, text });
  // Thresholds on one damaged text (750000 ppm) and on a clean one.
  for (const t of [0, 1, 750000, 750001, 975000, 1000000]) {
    add({ id: `g${String(cases.length + 1).padStart(3, "0")}`, note: `damaged text, threshold ${t}`, text: "कखग�", threshold_ppm: t });
  }
  for (const t of [0, 975000, 1000000]) {
    add({ id: `g${String(cases.length + 1).padStart(3, "0")}`, note: `clean text, threshold ${t}`, text: "नमस्ते।", threshold_ppm: t });
  }
  add({ id: `g${String(cases.length + 1).padStart(3, "0")}`, note: "Latin text with threshold 1000000 stays not scored", text: "hello", threshold_ppm: 1000000 });
  // The Devanagari share boundary and the size boundary, built from parts.
  add({ id: `g${String(cases.length + 1).padStart(3, "0")}`, note: "250000 Devanagari letters against 250001 Latin: 499999 ppm, not scored", parts: [[KA, 250000], ["a", 250001]] });
  add({ id: `g${String(cases.length + 1).padStart(3, "0")}`, note: "250000 against 250000: 500000 ppm, scored", parts: [[KA, 250000], ["a", 250000]] });
  add({ id: `g${String(cases.length + 1).padStart(3, "0")}`, note: "about 1 MiB of clean Hindi", parts: [["नमस्ते दुनिया।\n", 40000]] });
  add({ id: `g${String(cases.length + 1).padStart(3, "0")}`, note: "exactly 4 MiB of ASCII is accepted (not scored)", parts: [["a", 4194304]] });
  add({ id: `g${String(cases.length + 1).padStart(3, "0")}`, note: "4 MiB + 1 byte is refused", parts: [["a", 4194305]] });

  // C. ill-formed strings (a lone surrogate): refused by every binding.
  const ill = [
    ["a lone high surrogate", "\ud800"],
    ["a lone low surrogate", "\udc00"],
    ["a reversed pair", "\ude00\ud83d"],
    ["a high surrogate in the middle of Hindi", "न\ud800म"],
    ["a high surrogate at the end of Hindi", "नमस्ते\ud83d"],
    ["a low surrogate at the start of Hindi", "\udfffनम"],
  ];
  for (const [note, text] of ill) add({ id: `g${String(cases.length + 1).padStart(3, "0")}`, note: `ill-formed: ${note}`, text });

  // D. seeded mixtures and mutations of the invented corpus sentences, to fill the rest.
  const lines = readFileSync(join(root, "bench", "corpus", "clean.txt"), "utf8").split("\n").filter((l) => l !== "");
  const next = rng(0x5eed5eed5eed5eedn);
  const pick = (n) => next() % n;
  const MARKS = ["ा", "ि", "ी", "ु", "े", "्", "़", "ं", "ः", "‍", "‌", "�", "\u0001", "́"];
  const LATIN = ["data", "quality", "text", "the", "of", "OCR", "page", "2026", "ok"];
  const THRESHOLDS = [null, null, null, null, 0, 900000, 950000, 975000, 990000, 1000000];
  let n = 0;
  while (cases.length < TOTAL) {
    n += 1;
    let chars = Array.from(lines[pick(lines.length)]);
    if (pick(3) === 0) chars = chars.concat(Array.from(` ${lines[pick(lines.length)]}`));
    const steps = pick(8); // 0 to 7 mutations
    for (let k = 0; k < steps; k += 1) {
      const at = pick(chars.length + 1);
      switch (pick(5)) {
        case 0: chars.splice(at, 0, MARKS[pick(MARKS.length)]); break; // insert a mark or a bad character
        case 1: if (chars.length > 1) chars.splice(at % chars.length, 1); break; // delete
        case 2: if (chars.length > 1) { const i = at % (chars.length - 1); [chars[i], chars[i + 1]] = [chars[i + 1], chars[i]]; } break; // swap
        case 3: chars.splice(at, 0, ...Array.from(` ${LATIN[pick(LATIN.length)]} `)); break; // a Latin word, lowering the share
        default: chars.splice(at, 0, MARKS[pick(MARKS.length)], MARKS[pick(MARKS.length)]); // two bad marks in a row
      }
    }
    if (n % 9 === 0) chars = Array.from(`${LATIN.slice(0, 1 + pick(5)).join(" ")} ${chars.join("")} ${LATIN.slice(2, 2 + pick(5)).join(" ")}`); // Latin-heavy
    add({ id: `g${String(cases.length + 1).padStart(3, "0")}`, note: `seeded mixture ${n}`, text: chars.join(""), threshold_ppm: THRESHOLDS[pick(THRESHOLDS.length)] });
  }
  if (cases.length !== TOTAL) throw new Error(`the corpus has ${cases.length} cases, not ${TOTAL}`);
  return cases;
}

const caseLine = (c) => {
  const body = "parts" in c ? `"parts":${esc(c.parts)}` : `"text":${esc(c.text)}`;
  return `{"id":${esc(c.id)},${body},"threshold_ppm":${c.threshold_ppm === null ? "null" : c.threshold_ppm},"note":${esc(c.note)}}`;
};

function nativeExpected(cases, cli) {
  return cases.map((c) => {
    const text = textOf(c);
    const args = ["gate", ...(c.threshold_ppm === null ? [] : ["--threshold-ppm", String(c.threshold_ppm)]), "-"];
    const r = spawnSync(cli, args, { input: wtf8(text), maxBuffer: 1 << 28 });
    if (r.status === 0) return r.stdout.toString("utf8").replace(/\n$/, "");
    if (r.status === 1 || r.status === 2) return "rejected";
    throw new Error(`${c.id}: glyphsift gate exited ${r.status}: ${r.stderr}`);
  });
}

const mode = process.argv[2];
{
  const cases = build();
  const casesText = `${cases.map(caseLine).join("\n")}\n`;
  const cliIdx = process.argv.indexOf("--cli");
  const cli = resolve(root, cliIdx >= 0 ? process.argv[cliIdx + 1] : `target/release/glyphsift${process.platform === "win32" ? ".exe" : ""}`);
  if (mode === "--write") {
    writeFileSync(join(dir, "cases.jsonl"), casesText);
    const expected = nativeExpected(cases, cli);
    writeFileSync(join(dir, "expected.jsonl"), `${expected.join("\n")}\n`);
    console.log(`wrote ${cases.length} cases and their expected lines`, JSON.stringify(tally(expected)));
  } else if (mode === "--check") {
    const have = readFileSync(join(dir, "cases.jsonl"), "utf8");
    const lines = readFileSync(join(dir, "expected.jsonl"), "utf8").split("\n").filter((l) => l !== "");
    let bad = 0;
    if (have !== casesText) {
      console.error("FAIL tests/determinism/gate/cases.jsonl differs from what scripts/make-gate-corpus.mjs generates");
      bad += 1;
    } else console.log(`ok   cases.jsonl is exactly what the generator writes (${cases.length} cases)`);
    if (lines.length !== cases.length) {
      console.error(`FAIL expected.jsonl has ${lines.length} lines for ${cases.length} cases`);
      bad += 1;
    } else console.log(`ok   expected.jsonl has one line per case (${lines.length})`);
    process.exit(bad === 0 ? 0 : 1);
  } else {
    console.error("usage: make-gate-corpus.mjs --write [--cli <glyphsift binary>] | --check");
    process.exit(2);
  }
}
