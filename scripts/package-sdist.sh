#!/usr/bin/env bash
# Build the glyphsift sdist so that it builds `cargo build --locked` from its own Cargo.lock (S1-103, BUG-T2-S4-21).
#
#   scripts/package-sdist.sh
#
# `maturin sdist` (1.16.0) writes a workspace manifest with two members (glyphsift-core and glyphsift-py) next to the
# repository's whole Cargo.lock, so the unpacked sdist cannot build --locked: cargo wants to drop the lock entries
# of glyphsift-cli, glyphsift-wasm and the crates only they use. scripts/prune-sdist-lock.py removes exactly those
# entries (no version or checksum changes), and this script then proves the result: it unpacks the sdist in scratch,
# runs `cargo build --locked -p glyphsift-py` there and checks that Cargo.lock came out byte-identical. It does not
# publish anything, and `maturin sdist` compiles nothing itself. scripts/add-sdist-files.py then adds bench/corpus/clean.txt,
# docs/gate.md, docs/score-vs-noise.csv and docs/corruption-generator.md (synthetic, own-authored) that the shipped tests read.
#
# Environment: SDIST_OUT (default dist/sdist, relative to the repository, or absolute) is where glyphsift-<version>.tar.gz
# is written; any glyphsift-*.tar.gz already there is removed first. SDIST_VERIFY=0 skips the cargo build (the script
# test tests/scripts/sdist-locked.sh builds it itself). GLYPHSIFT_TOOLS_VENV (the hashed venv CI makes, see
# scripts/package-python.sh) or a maturin on PATH of exactly the pinned version in tools/ci/requirements.in is used
# first; otherwise the tool comes from `uvx maturin@<pin>`, pinned by version only (the local, unhashed path).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=${SDIST_OUT:-dist/sdist}
case "$OUT" in
  ""|[A-Za-z]:*|*\\*|..|../*|*/..|*/../*) echo "error: SDIST_OUT must be a non-empty path without backslashes, drive letters or '..' segments (got '$OUT')" >&2; exit 2 ;;
esac
VERSION=$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
[ -n "$VERSION" ] || { echo "error: no workspace version in Cargo.toml" >&2; exit 1; }
MATURIN_VERSION=$(sed -n 's/^maturin==\(.*\)$/\1/p' tools/ci/requirements.in | head -1)
[ -n "$MATURIN_VERSION" ] || { echo "error: tools/ci/requirements.in does not pin maturin" >&2; exit 1; }

if [ -n "${GLYPHSIFT_TOOLS_VENV:-}" ]; then
  if [ -d "$GLYPHSIFT_TOOLS_VENV/Scripts" ]; then TOOLS_BIN=$GLYPHSIFT_TOOLS_VENV/Scripts; else TOOLS_BIN=$GLYPHSIFT_TOOLS_VENV/bin; fi
  [ -d "$TOOLS_BIN" ] || { echo "error: GLYPHSIFT_TOOLS_VENV ($GLYPHSIFT_TOOLS_VENV) has no bin or Scripts directory" >&2; exit 1; }
  MATURIN=("$(cd "$TOOLS_BIN" && pwd -P)/maturin")
  FROM="the hashed venv $GLYPHSIFT_TOOLS_VENV"
elif command -v maturin >/dev/null 2>&1 && [ "$(maturin --version)" = "maturin $MATURIN_VERSION" ]; then
  MATURIN=(maturin)
  FROM="maturin $MATURIN_VERSION on PATH"
else
  MATURIN=(uvx "maturin@$MATURIN_VERSION")
  FROM="uvx, pinned by version only"
fi
GOT=$("${MATURIN[@]}" --version)
[ "$GOT" = "maturin $MATURIN_VERSION" ] || { echo "error: got '$GOT', want 'maturin $MATURIN_VERSION'" >&2; exit 1; }
echo "== tools: maturin $MATURIN_VERSION (from $FROM)"

mkdir -p "$OUT"
# Only sdists of this package are removed, and only from the output directory.
find "$OUT" -maxdepth 1 -name 'glyphsift-*.tar.gz' -type f -delete
echo "== maturin sdist (glyphsift $VERSION)"
"${MATURIN[@]}" sdist -m crates/glyphsift-py/Cargo.toml -o "$OUT"
SDIST=$OUT/glyphsift-$VERSION.tar.gz
[ -f "$SDIST" ] || { echo "error: $SDIST was not written" >&2; exit 1; }

echo "== prune the sdist's Cargo.lock to the packages its own workspace needs"
python3 -I scripts/prune-sdist-lock.py "$SDIST"

echo "== add the four repository-root files the glyphsift-core tests read (BUG-T2-S5-12, S1-118)"
python3 -I scripts/add-sdist-files.py "$SDIST"

if [ "${SDIST_VERIFY:-1}" != 0 ]; then
  echo "== verify: unpack, cargo build --locked -p glyphsift-py, Cargo.lock unchanged"
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/glyphsift-sdist-verify.XXXXXX")
  WORK=$(cd "$WORK" && pwd -P)
  cleanup() { case "$WORK" in /*/glyphsift-sdist-verify.??????) rm -rf "$WORK" ;; esac; }
  trap cleanup EXIT
  tar -xzf "$SDIST" -C "$WORK"
  cp "$WORK/glyphsift-$VERSION/Cargo.lock" "$WORK/Cargo.lock.before"
  ( cd "$WORK/glyphsift-$VERSION" && CARGO_TARGET_DIR="$WORK/target" cargo build --locked -p glyphsift-py )
  cmp "$WORK/glyphsift-$VERSION/Cargo.lock" "$WORK/Cargo.lock.before" || { echo "error: cargo changed the sdist's Cargo.lock" >&2; exit 1; }
  echo "ok: the sdist builds --locked from its own Cargo.lock"
fi
echo "sdist: $SDIST ($(wc -c < "$SDIST" | tr -d ' ') bytes)"
