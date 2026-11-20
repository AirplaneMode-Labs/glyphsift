#!/usr/bin/env node
// Assert what a release directory may hold before anything is uploaded from it (Sprint 7, D3-02, TD-118).
//
//   node scripts/release/assert-release-dir.mjs <dir>
//
// <dir> is the flat release directory (dist-release/). It must be a real directory (not a link) holding only regular files: the artefacts
// listed in release-manifest.json (one entry each, id = url = file name), release-manifest.json itself and SHA256SUMS, and nothing else;
// no subdirectory, no link; no name that looks like a credential or key (.npmrc, .pypirc, *.pem, *.key, *.der, *.pkcs8, anything with
// 'seed' in it, in any case). SHA256SUMS must use LF only, hold one '<64 hex>  <name>' line per entry, sorted by name, and its hashes and the
// manifest's must equal the files' real SHA-256. Exit 0 when all of that holds, 1 otherwise (one line per failure). No network, no environment.
import { createHash } from "node:crypto";
import { lstatSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const dir = process.argv[2];
if (!dir) {
  console.error("usage: assert-release-dir.mjs <dir>");
  process.exit(2);
}
const MANIFEST = "release-manifest.json";
const SUMS = "SHA256SUMS";
const FORBIDDEN = /^\.npmrc$|^\.pypirc$|\.pem$|\.key$|\.der$|\.pkcs8$|seed/i;
const bad = [];
const fail = (m) => bad.push(m);

let st;
try {
  st = lstatSync(dir);
} catch {
  console.error(`FAIL ${dir} does not exist`);
  process.exit(1);
}
if (st.isSymbolicLink() || !st.isDirectory()) fail(`${dir} is not a real directory`);

const names = readdirSync(dir).sort();
for (const n of names) {
  const s = lstatSync(join(dir, n));
  if (!s.isFile() || s.isSymbolicLink()) fail(`${n} is not a regular file`);
  if (FORBIDDEN.test(n)) fail(`${n} looks like credential or key material`);
}
for (const must of [MANIFEST, SUMS]) if (!names.includes(must)) fail(`${must} is missing`);

if (names.includes(MANIFEST) && names.includes(SUMS)) {
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(join(dir, MANIFEST), "utf8"));
  } catch (e) {
    fail(`${MANIFEST} is not JSON: ${e.message}`);
  }
  if (manifest) {
    const entries = Array.isArray(manifest.entries) ? manifest.entries : [];
    const listed = entries.map((e) => e.id).sort();
    const files = names.filter((n) => n !== MANIFEST && n !== SUMS);
    if (JSON.stringify(listed) !== JSON.stringify(files)) fail(`the manifest entries (${listed.join(", ")}) are not exactly the other files (${files.join(", ")})`);
    for (const e of entries) {
      if (e.id !== e.url) fail(`entry ${e.id}: id and url differ`);
      if (!files.includes(e.id)) continue;
      const bytes = readFileSync(join(dir, e.id));
      const sha = createHash("sha256").update(bytes).digest("hex");
      if (sha !== e.sha256) fail(`entry ${e.id}: sha256 differs from the file`);
      if (bytes.length !== e.size) fail(`entry ${e.id}: size differs from the file`);
    }
    const raw = readFileSync(join(dir, SUMS));
    const text = raw.toString("utf8");
    if (raw.includes(0x0d)) fail(`${SUMS} contains a carriage return (LF only)`);
    if (!text.endsWith("\n")) fail(`${SUMS} has no final newline`);
    const lines = text.split("\n").slice(0, -1);
    const want = entries
      .map((e) => `${e.sha256}  ${e.id}`)
      .sort((a, b) => (a.split("  ")[1] < b.split("  ")[1] ? -1 : 1));
    if (JSON.stringify(lines) !== JSON.stringify(want)) fail(`${SUMS} is not exactly one sorted '<sha256>  <name>' line per manifest entry`);
    console.log(`entries: ${entries.length}; files: ${names.length}`);
  }
}

if (bad.length) {
  for (const m of bad) console.log(`FAIL ${m}`);
  console.log(`release directory ${dir}: ${bad.length} problem(s)`);
  process.exit(1);
}
console.log(`ok   release directory ${dir} holds only the manifest entries, ${MANIFEST} and ${SUMS}`);
