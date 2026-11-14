#!/usr/bin/env bash
# S1-079: the Playwright install used by the demo-browser and packaging CI jobs (and by the owner) goes
# through a committed package-lock.json and `npm ci --ignore-scripts`, so every package is pinned by
# integrity hash. This test checks that lockfile, and the hashed Python requirements next to it, without
# the network. Written before the files existed (red-D3-02-lockfile.log).
#
# Lockfile: lockfileVersion 3; every entry under "packages" other than the root has a sha512 `integrity`
# and an https registry `resolved` URL, and is not a link, a git or a file dependency; package.json pins
# playwright to the exact version 1.65.0 and the lock's root lists the same dependencies.
# Requirements: tools/ci/requirements.txt pins every package with == and gives each at least one
# --hash=sha256 line, with no URL, editable or unpinned line; every package in requirements.in appears.
#
# LOCK_DIR overrides tools/playwright and REQ_DIR overrides tools/ci (the negative cases below use scratch
# copies with one hash or one integrity removed and must fail).
set -uo pipefail
. "$(dirname "$0")/lib.sh"

command -v node >/dev/null || { echo "SKIP - node not found"; exit 0; }
LOCK_DIR=${LOCK_DIR:-$REPO/tools/playwright}
REQ_DIR=${REQ_DIR:-$REPO/tools/ci}
SCRATCH=$(mktemp -d)
[ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] || { echo "error: mktemp -d failed" >&2; exit 1; }
trap '[ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"' EXIT

cat > "$SCRATCH/check-lock.mjs" <<'JS'
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
const dir = process.argv[2];
const errs = [];
const need = (ok, msg) => { if (!ok) errs.push(msg); };
const lockPath = join(dir, "package-lock.json");
const pkgPath = join(dir, "package.json");
need(existsSync(lockPath), `${lockPath} is missing`);
need(existsSync(pkgPath), `${pkgPath} is missing`);
if (errs.length) { console.error(errs.join("\n")); process.exit(1); }
const lock = JSON.parse(readFileSync(lockPath, "utf8"));
const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
need(lock.lockfileVersion === 3, `lockfileVersion is ${lock.lockfileVersion}, want 3`);
const entries = Object.entries(lock.packages ?? {}).filter(([k]) => k !== "");
need(entries.length >= 2, `only ${entries.length} package entries (playwright and playwright-core expected)`);
for (const [k, v] of entries) {
  need(typeof v.integrity === "string" && /^sha512-[A-Za-z0-9+/]+={0,2}$/.test(v.integrity), `${k}: no sha512 integrity`);
  need(typeof v.resolved === "string" && v.resolved.startsWith("https://registry.npmjs.org/"), `${k}: resolved is not an https registry.npmjs.org URL (${v.resolved})`);
  need(!v.link, `${k}: is a link`);
  need(!/^(git|file|github|http:)/.test(String(v.resolved ?? "")), `${k}: git, file or plain-http source`);
}
const deps = { ...(pkg.dependencies ?? {}), ...(pkg.devDependencies ?? {}) };
need(deps.playwright === "1.65.0", `package.json playwright is '${deps.playwright}', want exactly 1.65.0`);
for (const [n, r] of Object.entries(deps)) need(/^\d+\.\d+\.\d+$/.test(r), `package.json ${n} is '${r}', not an exact version`);
const root = { ...(lock.packages?.[""]?.dependencies ?? {}), ...(lock.packages?.[""]?.devDependencies ?? {}) };
need(JSON.stringify(Object.entries(root).sort()) === JSON.stringify(Object.entries(deps).sort()), "the lock's root dependencies differ from package.json");
need(lock.packages?.["node_modules/playwright"]?.version === "1.65.0", "the locked playwright is not 1.65.0");
need(lock.packages?.["node_modules/playwright-core"]?.version === "1.65.0", "the locked playwright-core is not 1.65.0");
need(pkg.scripts === undefined, "package.json has a scripts field");
if (errs.length) { console.error(errs.join("\n")); process.exit(1); }
console.log(`${entries.length} packages, every one with a sha512 integrity and a registry URL`);
JS

cat > "$SCRATCH/check-req.mjs" <<'JS'
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
const dir = process.argv[2];
const errs = [];
const need = (ok, msg) => { if (!ok) errs.push(msg); };
const txtPath = join(dir, "requirements.txt");
const inPath = join(dir, "requirements.in");
need(existsSync(txtPath), `${txtPath} is missing`);
need(existsSync(inPath), `${inPath} is missing`);
if (errs.length) { console.error(errs.join("\n")); process.exit(1); }
const lines = readFileSync(txtPath, "utf8").split("\n");
const pkgs = new Map();
let cur = null;
for (const raw of lines) {
  const line = raw.replace(/\s+$/, "");
  if (line.trim() === "" || line.trim().startsWith("#")) continue;
  let m = /^([A-Za-z0-9][A-Za-z0-9._-]*)==([0-9][^\s;\\]*)(\s*;[^\\]*)?\s*\\?$/.exec(line);
  if (m) { cur = m[1].toLowerCase().replace(/_/g, "-"); pkgs.set(cur, { version: m[2], hashes: 0 }); continue; }
  m = /^\s+--hash=sha256:([0-9a-f]{64})\s*\\?$/.exec(line);
  if (m && cur) { pkgs.get(cur).hashes += 1; continue; }
  errs.push(`unexpected line (not 'name==version' or '--hash=sha256:<64 hex>'): ${line.slice(0, 80)}`);
}
for (const [n, p] of pkgs) need(p.hashes >= 1, `${n}==${p.version} has no --hash line`);
const wanted = readFileSync(inPath, "utf8").split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("#"));
need(wanted.length >= 4, `requirements.in lists ${wanted.length} tools, expected uv, maturin, mypy and ziglang`);
for (const w of wanted) {
  const m = /^([A-Za-z0-9._-]+)==(\S+)$/.exec(w);
  need(Boolean(m), `requirements.in line is not an exact pin: ${w}`);
  if (m) need(pkgs.get(m[1].toLowerCase())?.version === m[2], `requirements.txt does not pin ${w}`);
}
for (const t of ["uv", "maturin", "mypy", "ziglang"]) need(pkgs.has(t), `${t} is not in requirements.txt`);
if (errs.length) { console.error(errs.join("\n")); process.exit(1); }
console.log(`${pkgs.size} packages, ${[...pkgs.values()].reduce((a, p) => a + p.hashes, 0)} hashes, every package pinned and hashed`);
JS

echo "== the committed lockfile and hashed requirements"
expect_eq "tools/playwright lockfile: every package has integrity, exact pins" 0 "$(node "$SCRATCH/check-lock.mjs" "$LOCK_DIR" >"$SCRATCH/lock.out" 2>&1; echo $?)"
cat "$SCRATCH/lock.out"
expect_eq "tools/ci/requirements.txt: every package pinned with at least one hash" 0 "$(node "$SCRATCH/check-req.mjs" "$REQ_DIR" >"$SCRATCH/req.out" 2>&1; echo $?)"
cat "$SCRATCH/req.out"

echo "== negative cases: a scratch copy with one integrity or one hash removed must fail"
if [ -f "$LOCK_DIR/package-lock.json" ]; then
  mkdir -p "$SCRATCH/lock-bad"
  cp "$LOCK_DIR/package.json" "$SCRATCH/lock-bad/package.json"
  node -e 'const fs=require("fs");const l=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));delete l.packages["node_modules/playwright-core"].integrity;fs.writeFileSync(process.argv[2],JSON.stringify(l,null,2))' "$LOCK_DIR/package-lock.json" "$SCRATCH/lock-bad/package-lock.json"
  expect_eq "a lockfile entry without integrity is refused" 1 "$(node "$SCRATCH/check-lock.mjs" "$SCRATCH/lock-bad" >/dev/null 2>&1; echo $?)"
  node -e 'const fs=require("fs");const l=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));l.packages["node_modules/playwright"].resolved="http://registry.npmjs.org/playwright/-/playwright-1.65.0.tgz";fs.writeFileSync(process.argv[2],JSON.stringify(l,null,2))' "$LOCK_DIR/package-lock.json" "$SCRATCH/lock-bad/package-lock.json"
  expect_eq "a lockfile entry over plain http is refused" 1 "$(node "$SCRATCH/check-lock.mjs" "$SCRATCH/lock-bad" >/dev/null 2>&1; echo $?)"
  sed 's/"playwright": "1.65.0"/"playwright": "^1.65.0"/' "$LOCK_DIR/package.json" > "$SCRATCH/lock-bad/package.json"
  cp "$LOCK_DIR/package-lock.json" "$SCRATCH/lock-bad/package-lock.json"
  expect_eq "a caret range in package.json is refused" 1 "$(node "$SCRATCH/check-lock.mjs" "$SCRATCH/lock-bad" >/dev/null 2>&1; echo $?)"
else
  fail "no lockfile to derive the negative cases from"
fi
if [ -f "$REQ_DIR/requirements.txt" ]; then
  mkdir -p "$SCRATCH/req-bad"
  cp "$REQ_DIR/requirements.in" "$SCRATCH/req-bad/requirements.in"
  # drop every hash line of maturin: the package line stays, its hashes go
  awk '/^[A-Za-z]/{skip=($1 ~ /^maturin==/)} !(skip && /--hash=/){print}' "$REQ_DIR/requirements.txt" > "$SCRATCH/req-bad/requirements.txt"
  expect_eq "a requirement without any hash is refused" 1 "$(node "$SCRATCH/check-req.mjs" "$SCRATCH/req-bad" >/dev/null 2>&1; echo $?)"
  sed 's/^mypy==2.4.1 \\$/mypy>=2.4.1 \\/' "$REQ_DIR/requirements.txt" > "$SCRATCH/req-bad/requirements.txt"
  expect_eq "an unpinned requirement is refused" 1 "$(node "$SCRATCH/check-req.mjs" "$SCRATCH/req-bad" >/dev/null 2>&1; echo $?)"
else
  fail "no requirements.txt to derive the negative cases from"
fi

finish
