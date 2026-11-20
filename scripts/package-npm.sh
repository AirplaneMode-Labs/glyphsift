#!/usr/bin/env bash
# Assemble the npm package @airplanemode/glyphsift from the WASM build (dist/wasm/{web,nodejs}) into
# dist/npm, pack it, install the tarball offline into a fresh empty directory, and check it (tarball
# contents, package.json, packaged README, one package installed, a Node call, and, when
# PLAYWRIGHT_DIR is set, a bundler-free page in installed Chrome). It does NOT publish: the npm scope
# is not reserved, and publishing is the owner's step.
#
#   scripts/build-wasm.sh && scripts/package-npm.sh
#
# The package has two builds: nodejs/ (CommonJS, loads the .wasm synchronously; the `node` entry) and
# web/ (an ES module, init() then the functions; the `import` and default entries).
#
# Environment: WASM_OUT (default dist/wasm; a relative path inside the repository, same rules as
# build-wasm.sh); SCRATCH (a directory that does not exist yet, or empty; default a fresh mktemp -d)
# holds the install directory and the empty npm cache (it is resolved to its physical path, symlinks
# followed, before use); PLAYWRIGHT_DIR (tools/playwright
# after `npm ci --prefix tools/playwright --ignore-scripts`, or any directory with playwright@1.65.0
# installed) enables the browser check; CLI (default target/release/glyphsift) is
# the native binary the Node and browser output is compared with. PACKAGE_NPM_PACK_ONLY=1 (Sprint 7, scripts/release/rehearse.sh)
# stops after the builder-path gate with the tarball written and prints its path: the release rehearsal installs and calls the tarball
# itself, in its own fresh project on each operating system, and the native CLI is not needed for that. PYTHON (default python3) names
# the interpreter for the builder-path gate: a Windows runner has `python`, not always `python3`.
set -euo pipefail
cd "$(dirname "$0")/.."
# Physical paths only (BUG-T2-S3-19-R2): npm writes the tarball's file: dependency relative to the real
# path of the install directory and `npm ls --prefix` resolves it from the path it is given, so a path
# through a symlink (macOS: /var is a link to /private/var) made `npm ls` report the one installed
# package as invalid. The checkout path is resolved here and the scratch path below.
cd "$(pwd -P)"

# Same guard as build-wasm.sh: a set-but-empty, absolute, drive-letter, backslash or '..' path is refused.
SRC=${WASM_OUT-dist/wasm}
case "$SRC" in
  ""|/*|[A-Za-z]:*|*\\*|..|../*|*/..|*/../*) echo "error: WASM_OUT must be a non-empty relative path with forward slashes only, no drive letter and no '..' segments (got '$SRC')" >&2; exit 2 ;;
esac
for t in web nodejs; do
  [ -f "$SRC/$t/glyphsift_bg.wasm" ] && [ -f "$SRC/$t/glyphsift.js" ] && [ -f "$SRC/$t/glyphsift.d.ts" ] \
    || { echo "error: $SRC/$t is missing; run scripts/build-wasm.sh first" >&2; exit 1; }
done
VERSION=$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
[ -n "$VERSION" ] || { echo "error: no workspace version in Cargo.toml" >&2; exit 1; }
OUT=dist/npm
rm -rf "./$OUT"
mkdir -p "$OUT/package"
cp -R "$SRC/web" "$SRC/nodejs" "$OUT/package/"
cp LICENSE NOTICE "$OUT/package/"
cp npm/README.md "$OUT/package/README.md"
cat > "$OUT/package/package.json" <<JSON
{
  "name": "@airplanemode/glyphsift",
  "version": "$VERSION",
  "description": "Deterministic Devanagari grapheme-cluster validator for extracted Indic text (WASM build)",
  "license": "Apache-2.0",
  "repository": { "type": "git", "url": "git+https://github.com/AirplaneMode-Labs/glyphsift.git" },
  "keywords": ["devanagari", "unicode", "grapheme", "data-quality", "ocr", "wasm", "deterministic"],
  "main": "nodejs/glyphsift.js",
  "module": "web/glyphsift.js",
  "types": "web/glyphsift.d.ts",
  "exports": {
    ".": {
      "types": "./web/glyphsift.d.ts",
      "node": { "types": "./nodejs/glyphsift.d.ts", "default": "./nodejs/glyphsift.js" },
      "import": "./web/glyphsift.js",
      "default": "./web/glyphsift.js"
    },
    "./web": "./web/glyphsift.js",
    "./nodejs": "./nodejs/glyphsift.js",
    "./web/glyphsift_bg.wasm": "./web/glyphsift_bg.wasm"
  },
  "files": ["web", "nodejs", "README.md", "LICENSE", "NOTICE"],
  "sideEffects": false
}
JSON

( cd "$OUT" && npm pack --silent --ignore-scripts ./package --pack-destination . >/dev/null )
TARBALL=$(ls "$OUT"/*.tgz)
echo "packed $TARBALL ($(wc -c < "$TARBALL" | tr -d ' ') bytes)"
tar -tzf "$TARBALL" | sed 's/^/  /'
case "$TARBALL" in /*) TGZ=$TARBALL ;; *) TGZ=$PWD/$TARBALL ;; esac

echo "== builder-path gate: no packed file may contain /Users/, /home/ or /private/tmp"
"${PYTHON:-python3}" -I scripts/check-no-builder-paths.py "$TGZ"

if [ "${PACKAGE_NPM_PACK_ONLY:-0}" = 1 ]; then
  echo "packed only (PACKAGE_NPM_PACK_ONLY=1): $TGZ"
  exit 0
fi

# CARGO_TARGET_DIR (absolute, or relative to this directory as cargo reads it) decides where the build wrote the CLI (BUG-T2-S6-06).
CLI=${CLI:-${CARGO_TARGET_DIR:-target}/release/glyphsift}
[ -x "$CLI" ] || cargo build -q --release --locked -p glyphsift-cli

SCRATCH=${SCRATCH:-$(mktemp -d)}
mkdir -p "$SCRATCH"
SCRATCH=$(cd "$SCRATCH" && pwd -P)
INSTALL=$SCRATCH/install
CACHE=$SCRATCH/npm-cache-empty
for d in "$INSTALL" "$CACHE"; do
  if [ -e "$d" ] && [ -n "$(ls -A "$d" 2>/dev/null)" ]; then
    echo "error: $d already exists and is not empty; pass a fresh SCRATCH" >&2; exit 1
  fi
done
mkdir -p "$INSTALL" "$CACHE"
echo "== npm init -y, then npm i <tgz> --ignore-scripts --offline --no-audit --no-fund (empty cache $CACHE)"
( cd "$INSTALL" && npm init -y >/dev/null && npm i "$TGZ" --ignore-scripts --offline --no-audit --no-fund --cache "$CACHE" )
( cd "$INSTALL" && npm ls --all )

echo "== checks: tarball, package.json, README, one package, Node call"
node tests/npm/check_node.mjs --tgz "$TGZ" --dir "$INSTALL" --cli "$CLI"

if [ -n "${PLAYWRIGHT_DIR:-}" ]; then
  echo "== browser: bundler-free page in installed Chrome"
  node tests/npm/check_browser.mjs --dir "$INSTALL" --cli "$CLI" ${SHOTS:+--shots "$SHOTS"}
else
  echo "browser check skipped: run npm ci --prefix tools/playwright --ignore-scripts and set PLAYWRIGHT_DIR=tools/playwright"
fi
echo "npm package ok: @airplanemode/glyphsift $VERSION ($(basename "$TARBALL"))"
