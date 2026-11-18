#!/usr/bin/env node
// Write an UNSIGNED airplanemode.manifest/0.1 that lists release artifacts with their SHA-256 and size.
//
//   node scripts/release-manifest.mjs --out dist/release-manifest.json <artifact>...
//
// Node 22, no dependencies. This script has no signing option and never reads a key: signing is a
// separate step done by the owner on an offline key machine with `cp-sign` (docs/RELEASING.md, "Signing
// the manifest"). The output path must resolve (symlinks, junctions and 8.3 names included) to a regular file
// inside this repository's dist/ directory; the rules, the Windows-only rules and the residual check-then-write
// window are in scripts/lib/confine.mjs and docs/release.md ("Output confinement"). SOURCE_DATE_EPOCH (decimal
// seconds, 0..253402300799) fixes createdAt for reproducible output; without it the current time is used.
// Exit 0 on success, 2 on any refusal, 1 on a write error.
//
// Contract constants (shared with the pagetriage copy of this script; only these lines differ).
const MANIFEST_ID = "glyphsift-release";
const PUBLISHER = "Airplane Mode Labs";
const LICENCE = "Apache-2.0";
const VERSION_SOURCE = "Cargo.toml"; // [workspace.package] version, relative to the repository root
const MANIFEST_SPEC = "airplanemode.manifest/0.1";

import { createHash } from "node:crypto";
import { closeSync, openSync, readFileSync, readSync, statSync } from "node:fs";
import { basename, dirname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { Refusal, confineOutput, writeConfined } from "./lib/confine.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const ID_RE = /^[a-z0-9][a-z0-9._-]{0,127}$/;
const SEMVER_RE = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$/;
const MAX_EPOCH = 253402300799; // 9999-12-31T23:59:59Z

function refuse(msg) {
  process.stderr.write(`release-manifest: ${msg}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  let out;
  const artifacts = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--out") {
      if (out !== undefined || i + 1 >= argv.length) refuse("--out takes exactly one file");
      out = argv[++i];
    } else if (a.startsWith("-")) {
      refuse(`unknown option '${a}' (usage: --out <file> <artifact>...)`);
    } else {
      artifacts.push(a);
    }
  }
  if (!out) refuse("missing --out <file>");
  if (artifacts.length === 0) refuse("no artifacts given");
  return { out, artifacts };
}

function createdAt() {
  const raw = process.env.SOURCE_DATE_EPOCH;
  if (raw === undefined) return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  if (!/^[0-9]{1,13}$/.test(raw)) refuse(`SOURCE_DATE_EPOCH must be a decimal integer (got '${raw.slice(0, 40)}')`);
  const n = Number(raw);
  if (n > MAX_EPOCH) refuse(`SOURCE_DATE_EPOCH out of range 0..${MAX_EPOCH}`);
  return new Date(n * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");
}

function workspaceVersion() {
  const text = readFileSync(join(ROOT, VERSION_SOURCE), "utf8");
  const m = /^\[workspace\.package\]\s*$([\s\S]*?)(?=^\[|(?![\s\S]))/m.exec(text);
  const v = m && /^version\s*=\s*"([^"]+)"/m.exec(m[1]);
  if (!v || !SEMVER_RE.test(v[1])) refuse(`no valid [workspace.package] version in ${VERSION_SOURCE}`);
  return v[1];
}

function mediaType(name) {
  if (name.endsWith(".whl") || name.endsWith(".zip")) return "application/zip";
  if (name.endsWith(".tgz") || name.endsWith(".tar.gz") || name.endsWith(".crate")) return "application/gzip";
  if (name.endsWith(".json")) return "application/json";
  return "application/octet-stream";
}

function hashFile(path) {
  const h = createHash("sha256");
  const fd = openSync(path, "r");
  try {
    const buf = Buffer.allocUnsafe(1 << 20);
    for (let n; (n = readSync(fd, buf, 0, buf.length, null)) > 0; ) h.update(buf.subarray(0, n));
  } finally {
    closeSync(fd);
  }
  return h.digest("hex");
}

const { out, artifacts } = parseArgs(process.argv.slice(2));
const created = createdAt();
const version = workspaceVersion();
let plan;
try {
  plan = confineOutput(out, { root: ROOT });
} catch (e) {
  if (e instanceof Refusal) refuse(e.message);
  throw e;
}

const entries = [];
const seen = new Set();
for (const a of artifacts) {
  let st;
  try { st = statSync(a); } catch { refuse(`artifact not found: ${a}`); }
  if (!st.isFile()) refuse(`artifact is not a regular file: ${a}`);
  const url = basename(a);
  const id = url.toLowerCase();
  if (!ID_RE.test(id)) refuse(`artifact name '${url}' is not a valid entry id (${ID_RE})`);
  if (seen.has(id)) refuse(`duplicate entry id '${id}'`);
  seen.add(id);
  entries.push({ id, kind: "other", url, sha256: hashFile(a), size: st.size, version, licence: LICENCE, minProfile: {}, mediaType: mediaType(id) });
}
entries.sort((x, y) => (x.id < y.id ? -1 : x.id > y.id ? 1 : 0)); // ids are ASCII, so this is byte order

const manifest = { spec: MANIFEST_SPEC, id: MANIFEST_ID, version, publisher: PUBLISHER, createdAt: created, entries, signatures: [] };
try {
  writeConfined(plan, JSON.stringify(manifest, null, 2) + "\n");
} catch (e) {
  if (e instanceof Refusal) refuse(e.message);
  process.stderr.write(`release-manifest: could not write ${plan.target}: ${e && e.message}\n`);
  process.exit(1);
}
const shown = ["dist", ...plan.target.slice(plan.distReal.length).split(sep).filter(Boolean)].join("/");
process.stdout.write(`wrote unsigned manifest ${shown} (${entries.length} entries, version ${version})\n`);
