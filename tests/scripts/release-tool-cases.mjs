#!/usr/bin/env node
// Run every case of the shared release vectors (release.json) through the VENDORED release tool (Sprint 7, D3-01; TD-103, TD-104).
//
//   node tests/scripts/release-tool-cases.mjs --tool scripts/release/release-tool.mjs --vectors scripts/release/vectors
//
// The vectors are a byte-for-byte copy of runtime's spec/vectors/release (spec release 0.6.1); scripts/release/VENDORED.json records their digest. Each case
// starts from one of the committed directories, which is copied to a fresh temporary directory and mutated there (the committed files are never touched),
// runs `node <tool> <command> --dir <copy> <args>` with `@keys/<file>` arguments replaced by the committed keys files, and must give exactly the expected
// exit code and reason: exit 0 with the testKey flag read from the stdout JSON; exit 2 with the first stderr line `usage: <reason>:`; exit 3 with the first
// stderr line `refused: <reason>` and stdout {"verdict":"refused","reason":<reason>}. A case that applies on this operating system and cannot be set up
// (a link the OS refuses to make) FAILS: nothing is skipped. A case with a `platform` runs only there (the junction case, on Windows). The environment the
// tool sees holds no variable beyond PATH and the temporary directory settings: in particular no SOURCE_DATE_EPOCH and nothing from the runner.
// Exit 0 when every case passes. Nothing here reads a sibling repository or the network.
import { spawnSync } from "node:child_process";
import { copyFileSync, cpSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync, unlinkSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const argv = process.argv.slice(2);
const opt = (n) => argv[argv.indexOf(n) + 1];
const tool = argv.includes("--tool") ? resolve(opt("--tool")) : undefined;
const vectors = argv.includes("--vectors") ? resolve(opt("--vectors")) : undefined;
if (!tool || !vectors) {
  console.error("usage: release-tool-cases.mjs --tool <release-tool.mjs> --vectors <vectors dir>");
  process.exit(2);
}
const cases = JSON.parse(readFileSync(join(vectors, "release.json"), "utf8"));
const base = realpathSync(mkdtempSync(join(tmpdir(), "glyphsift-release-cases-")));
const env = { PATH: process.env.PATH ?? "", TEMP: process.env.TEMP ?? base, TMP: process.env.TMP ?? base, TMPDIR: process.env.TMPDIR ?? base };
if (process.env.SYSTEMROOT) env.SYSTEMROOT = process.env.SYSTEMROOT;

function mutate(op, dir, work) {
  const f = (name) => join(dir, name);
  switch (op.op) {
    case "none":
      return dir;
    case "flip-byte": {
      const b = readFileSync(f(op.file));
      b[op.offset] ^= 1;
      writeFileSync(f(op.file), b);
      return dir;
    }
    case "truncate": {
      const b = readFileSync(f(op.file));
      writeFileSync(f(op.file), b.subarray(0, b.length - op.bytes));
      return dir;
    }
    case "remove":
      unlinkSync(f(op.file));
      return dir;
    case "add-file":
      writeFileSync(f(op.file), op.content);
      return dir;
    case "sums-edit": {
      const lines = readFileSync(f("SHA256SUMS"), "utf8").split("\n");
      const l = lines[op.line];
      lines[op.line] = (l[0] === "0" ? "1" : "0") + l.slice(1);
      writeFileSync(f("SHA256SUMS"), lines.join("\n"));
      return dir;
    }
    case "sums-crlf":
      writeFileSync(f("SHA256SUMS"), readFileSync(f("SHA256SUMS"), "utf8").replace(/\n/g, "\r\n"));
      return dir;
    case "sums-reorder": {
      const lines = readFileSync(f("SHA256SUMS"), "utf8").split("\n").filter(Boolean).reverse();
      writeFileSync(f("SHA256SUMS"), lines.join("\n") + "\n");
      return dir;
    }
    case "manifest-publisher-edit": {
      const t = readFileSync(f("release-manifest.json"), "utf8");
      const edited = t.replace(/("publisher": ")([^"]*)(")/, "$1$2 (edited)$3");
      if (edited === t) throw new Error("the publisher member was not found in the manifest");
      writeFileSync(f("release-manifest.json"), edited);
      return dir;
    }
    case "symlink-artifact": {
      const outside = join(work, "outside-" + op.file);
      copyFileSync(f(op.file), outside);
      unlinkSync(f(op.file));
      symlinkSync(outside, f(op.file), "file");
      return dir;
    }
    case "junction-artifact": {
      const outside = join(work, "outside-dir");
      mkdirSync(outside);
      unlinkSync(f(op.file));
      symlinkSync(outside, f(op.file), "junction");
      return dir;
    }
    case "subdir":
      mkdirSync(f(op.name));
      return dir;
    case "symlink-dir": {
      const link = join(work, "dir-link");
      symlinkSync(dir, link, process.platform === "win32" ? "junction" : "dir");
      return link;
    }
    default:
      throw new Error("unknown mutation op " + op.op);
  }
}

let pass = 0;
let fail = 0;
let n = 0;
for (const c of cases) {
  if (c.platform && c.platform !== process.platform) {
    console.log(`na   ${c.name}: runs only on ${c.platform}`);
    continue;
  }
  n += 1;
  const work = mkdtempSync(join(base, "case-"));
  let problem = null;
  try {
    const copy = join(work, "dir");
    cpSync(join(vectors, c.dir), copy, { recursive: true });
    const runDir = mutate(c.mutation, copy, work);
    const args = c.args.map((a) => (a.startsWith("@keys/") ? join(vectors, "keys", a.slice(6)) : a));
    const r = spawnSync(process.execPath, [tool, c.command, "--dir", runDir, ...args], { env, encoding: "utf8" });
    const first = (r.stderr ?? "").split("\n")[0].replace(/\r$/, "");
    if (r.status !== c.expect.exit) problem = `exit ${r.status}, expected ${c.expect.exit} (stderr: ${first})`;
    else if (c.expect.exit === 0) {
      let j;
      try { j = JSON.parse(r.stdout); } catch { problem = "stdout is not JSON"; }
      if (!problem && (j.verdict !== "ok" || j.testKey !== c.expect.testKey)) problem = `stdout ${r.stdout.trim()} (expected verdict ok, testKey ${c.expect.testKey})`;
    } else if (c.expect.exit === 2) {
      if (!first.startsWith(`usage: ${c.expect.reason}:`)) problem = `first stderr line '${first}', expected 'usage: ${c.expect.reason}: ...'`;
    } else if (c.expect.exit === 3) {
      let j;
      try { j = JSON.parse(r.stdout); } catch { problem = "stdout is not JSON"; }
      if (first !== `refused: ${c.expect.reason}`) problem = `first stderr line '${first}', expected 'refused: ${c.expect.reason}'`;
      else if (!problem && (j.verdict !== "refused" || j.reason !== c.expect.reason)) problem = `stdout ${r.stdout.trim()}`;
    }
  } catch (e) {
    problem = `setup failed: ${e.message}`;
  }
  if (problem) {
    fail += 1;
    console.log(`FAIL ${c.name}: ${problem}`);
  } else {
    pass += 1;
    console.log(`ok   ${c.name} (${c.command} -> exit ${c.expect.exit}${c.expect.reason ? " " + c.expect.reason : ""})`);
  }
  rmSync(work, { recursive: true, force: true });
}
rmSync(base, { recursive: true, force: true });
console.log(`release vectors through ${tool.split(/[\\/]/).pop()}: ${pass} of ${n} cases passed, ${fail} failed`);
process.exit(fail === 0 && n > 0 ? 0 : 1);
