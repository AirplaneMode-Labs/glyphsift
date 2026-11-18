#!/usr/bin/env bash
# S1-103 / BUG-T2-S4-21: the sdist builds `--locked` from its own Cargo.lock.
#
#   tests/scripts/sdist-locked.sh
#
# Before the fix, `maturin sdist` wrote a workspace manifest with two members (core and py) next to the
# whole workspace's Cargo.lock (cli and wasm included, 61 packages), so `cargo build --locked` on the unpacked
# sdist stopped with "cannot update the lock file" (red log: D3-02 sdist-locked-repro.log). scripts/package-sdist.sh
# builds the sdist and prunes that lock to the packages the sdist's own workspace needs, changing no version and no checksum.
#
# This test builds the sdist with scripts/package-sdist.sh, unpacks it in scratch and checks that:
#   - there is exactly one sdist, glyphsift-<workspace version>.tar.gz, under 5 MB;
#   - it carries Cargo.toml, Cargo.lock, README.md, pyproject.toml, LICENSE and NOTICE (root and each crate shipped);
#   - no packed file contains a builder path (scripts/check-no-builder-paths.py);
#   - its Cargo.lock lists only packages of the repository's Cargo.lock, at the same versions and checksums, and fewer;
#   - `cargo build --locked -p glyphsift-py` succeeds from the unpacked tree and leaves Cargo.lock byte-identical;
#   - (BUG-T2-S5-12) `cargo test --locked --no-fail-fast -p glyphsift-core` passes from the unpacked tree with 0 failed and
#     no --skip: the gate tests read bench/corpus/clean.txt, docs/gate.md and docs/score-vs-noise.csv, which the sdist ships at
#     the same relative paths (all three synthetic and own-authored).
#
# Tools: maturin comes from GLYPHSIFT_TOOLS_VENV (the hashed venv CI makes) or `uvx maturin@<pin>`, as in
# scripts/package-python.sh. The cargo build uses the network or the local registry cache. Nothing is published.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1

VERSION=$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
[ -n "$VERSION" ] || { echo "error: no workspace version in Cargo.toml" >&2; exit 1; }

# A fresh scratch directory, removed at the end (only this mktemp directory, never a variable path).
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/glyphsift-sdist.XXXXXX") || exit 1
SCRATCH=$(cd "$SCRATCH" && pwd -P)
# Only the mktemp directory created above is ever removed: the guard refuses any other shape of path.
cleanup() { case "$SCRATCH" in /*/glyphsift-sdist.??????) rm -rf "$SCRATCH" ;; esac; }
trap cleanup EXIT
OUT=$SCRATCH/out
UN=$SCRATCH/un
mkdir -p "$OUT" "$UN"

if [ ! -x scripts/package-sdist.sh ]; then
  fail "scripts/package-sdist.sh exists and is executable"
  finish; exit $?
fi
ok "scripts/package-sdist.sh exists and is executable"

SDIST_OUT=$OUT scripts/package-sdist.sh > "$SCRATCH/package-sdist.log" 2>&1
rc=$?
expect_eq "scripts/package-sdist.sh exits 0" 0 "$rc"
if [ "$rc" -ne 0 ]; then tail -20 "$SCRATCH/package-sdist.log"; fi

COUNT=$(find "$OUT" -maxdepth 1 -name '*.tar.gz' -type f | wc -l | tr -d ' ')
expect_eq "exactly one sdist is written" 1 "$COUNT"
TGZ=$OUT/glyphsift-$VERSION.tar.gz
if [ ! -f "$TGZ" ]; then
  fail "the sdist is $TGZ"
  finish; exit $?
fi
ok "the sdist is glyphsift-$VERSION.tar.gz"
SIZE=$(wc -c < "$TGZ" | tr -d ' ')
if [ "$SIZE" -lt 5242880 ]; then ok "the sdist is under 5 MB ($SIZE bytes)"; else fail "the sdist is under 5 MB (got $SIZE)"; fi

LIST=$(tar -tzf "$TGZ")
for f in Cargo.toml Cargo.lock README.md pyproject.toml LICENSE NOTICE \
         crates/glyphsift-core/Cargo.toml crates/glyphsift-core/LICENSE crates/glyphsift-core/NOTICE \
         crates/glyphsift-py/Cargo.toml crates/glyphsift-py/LICENSE crates/glyphsift-py/NOTICE; do
  if printf '%s\n' "$LIST" | grep -qxF "glyphsift-$VERSION/$f"; then ok "the sdist carries $f"; else fail "the sdist carries $f"; fi
done

python3 -I scripts/check-no-builder-paths.py "$TGZ" > "$SCRATCH/paths.log" 2>&1
expect_eq "no builder path in any packed file" 0 "$?"

tar -xzf "$TGZ" -C "$UN" 2>/dev/null
ROOT=$UN/glyphsift-$VERSION
[ -d "$ROOT" ] || { fail "the sdist unpacks to glyphsift-$VERSION/"; finish; exit $?; }

# The sdist's lock is a pruned copy: same versions and checksums, fewer packages.
python3 -I - "$REPO/Cargo.lock" "$ROOT/Cargo.lock" <<'PY'
import sys, tomllib
def pkgs(path):
    with open(path, "rb") as f:
        d = tomllib.load(f)
    return {(p["name"], p["version"], p.get("source", ""), p.get("checksum", "")) for p in d["package"]}
repo, sdist = pkgs(sys.argv[1]), pkgs(sys.argv[2])
extra = sdist - repo
print(f"repository lock: {len(repo)} packages; sdist lock: {len(sdist)} packages; in the sdist but not the repository: {len(extra)}")
for e in sorted(extra):
    print("  extra:", e)
ok = not extra and len(sdist) < len(repo)
sys.exit(0 if ok else 1)
PY
expect_eq "the sdist Cargo.lock is a strict subset of the repository's, same versions and checksums" 0 "$?"

cp "$ROOT/Cargo.lock" "$SCRATCH/Cargo.lock.before"
( cd "$ROOT" && CARGO_TARGET_DIR="$SCRATCH/target" cargo build --locked -p glyphsift-py ) > "$SCRATCH/build.log" 2>&1
rc=$?
expect_eq "cargo build --locked -p glyphsift-py succeeds from the unpacked sdist" 0 "$rc"
if [ "$rc" -ne 0 ]; then tail -8 "$SCRATCH/build.log"; fi
if cmp -s "$ROOT/Cargo.lock" "$SCRATCH/Cargo.lock.before"; then ok "cargo left the sdist's Cargo.lock byte-identical"; else fail "cargo left the sdist's Cargo.lock byte-identical"; fi

for f in bench/corpus/clean.txt docs/gate.md docs/score-vs-noise.csv; do
  if printf '%s\n' "$LIST" | grep -qxF "glyphsift-$VERSION/$f"; then ok "the sdist carries $f"; else fail "the sdist carries $f"; fi
done

( cd "$ROOT" && CARGO_TARGET_DIR="$SCRATCH/target" cargo test --locked --no-fail-fast -p glyphsift-core ) > "$SCRATCH/test.log" 2>&1
rc=$?
expect_eq "cargo test --locked -p glyphsift-core passes from the unpacked sdist" 0 "$rc"
FAILED=$(grep -E '^test result:' "$SCRATCH/test.log" | grep -oE '[0-9]+ failed' | awk '{s+=$1} END{print s+0}')
expect_eq "0 tests failed in the unpacked sdist" 0 "$FAILED"
if [ "$rc" -ne 0 ]; then grep -E '^test result:|panicked|FAILED' "$SCRATCH/test.log" | head -12; fi
cmp -s "$ROOT/Cargo.lock" "$SCRATCH/Cargo.lock.before" && ok "cargo test left the sdist's Cargo.lock byte-identical" || fail "cargo test left the sdist's Cargo.lock byte-identical"

finish
