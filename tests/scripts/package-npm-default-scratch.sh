#!/usr/bin/env bash
# BUG-T2-S3-19-R2: scripts/package-npm.sh failed on macOS when run with its default scratch folder.
# Written before the fix (red-D3-01.log).
#
# Cause. `SCRATCH=${SCRATCH:-$(mktemp -d)}` gives a path through a symlink on macOS (/var is a link to
# /private/var). npm writes the tarball's `file:` dependency relative to the REAL path of the install
# directory, and `npm ls --prefix <dir>` (tests/npm/check_node.mjs) resolves it from the path it was
# given. When the tarball's path and the install directory's real path share a leading directory, the two
# disagree and `npm ls` reports ELSPROBLEMS "invalid" for the one installed package. T2 hit it from a
# checkout in a temp directory; a checkout in the home directory shares no prefix with the scratch folder,
# which is why the plain run below (part 1) passes on a Mac even with the old script.
#
# The test therefore has two parts:
#   1. the spec'd case: scripts/build-wasm.sh, then scripts/package-npm.sh with SCRATCH unset, in the real
#      checkout;
#   2. the same script, in a scratch copy of the layout that sits under the default temp area and is run
#      from its PHYSICAL path. That makes the shared-prefix condition true on macOS wherever the real
#      checkout lives (the default scratch is /private/var/folders/..., the layout is under it too, and the
#      script is reached through the /var link). Where mktemp honours TMPDIR (Linux), TMPDIR is also set
#      to a symlink whose target is deeper than the link and sits beside the layout, which creates the same
#      condition without macOS. The old script fails here; the fixed one does not.
#
# SCRIPTS_DIR (lib.sh) overrides where part 2 takes package-npm.sh from, to run the test against an older copy:
#   mkdir -p "$X" && git show HEAD~N:scripts/package-npm.sh > "$X/package-npm.sh" && SCRIPTS_DIR=$X tests/scripts/package-npm-default-scratch.sh
# (part 1 always runs the checked-in scripts).
# No network call, no publish: package-npm.sh installs the tarball offline into a fresh directory.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

command -v node >/dev/null || { echo "SKIP - node not found"; exit 0; }
command -v npm >/dev/null || { echo "SKIP - npm not found"; exit 0; }

BASE=$(mktemp -d)
[ -n "$BASE" ] && [ -d "$BASE" ] || { echo "error: mktemp -d failed" >&2; exit 1; }
cleanup() { [ -n "$BASE" ] && [ -d "$BASE" ] && rm -rf "$BASE"; }
trap cleanup EXIT

# The native CLI that package-npm.sh compares the Node output with. Build it once, here, so that part 2's
# layout copy does not need a Rust build.
case "${CARGO_TARGET_DIR:-}" in
  "") TGT_DIR=$REPO/target ;; /*|[A-Za-z]:*) TGT_DIR=$CARGO_TARGET_DIR ;; *) TGT_DIR=$REPO/$CARGO_TARGET_DIR ;; esac
CLI=${CLI:-$TGT_DIR/release/glyphsift}
if [ ! -x "$CLI" ]; then
  ( cd "$REPO" && cargo build -q --release --locked -p glyphsift-cli ) || { echo "error: cargo build of the CLI failed" >&2; exit 1; }
fi

# ---- 1. the real checkout, SCRATCH unset ----------------------------------------------------------
echo "== 1. scripts/build-wasm.sh, then scripts/package-npm.sh with SCRATCH unset (real checkout)"
( cd "$REPO" && "$REPO/scripts/build-wasm.sh" ) > "$BASE/build-wasm.log" 2>&1
expect_eq "build-wasm.sh exits 0" 0 "$?"
mkdir -p "$BASE/tmp-default"
( cd "$REPO" && env -u SCRATCH TMPDIR="$BASE/tmp-default" CLI="$CLI" "$REPO/scripts/package-npm.sh" ) > "$BASE/p1.log" 2>&1
expect_eq "package-npm.sh with SCRATCH unset exits 0" 0 "$?"
if [ "$FAILS" -ne 0 ]; then tail -25 "$BASE/p1.log"; fi
expect_eq "it ends with 'npm package ok'" 1 "$(grep -c '^npm package ok: @airplanemode/glyphsift ' "$BASE/p1.log")"
expect_eq "npm ls found the one installed package" 1 "$(grep -c 'npm ls --all shows exactly one package' "$BASE/p1.log")"

# ---- 2. a scratch copy of the layout under the default temp area, run from its physical path --------
echo "== 2. the same script from a layout copy under the temp area (physical path), default scratch"
if [ ! -d "$REPO/dist/wasm/web" ] || [ ! -d "$REPO/dist/wasm/nodejs" ]; then
  fail "dist/wasm is missing after build-wasm.sh"
else
  PBASE=$(cd "$BASE" && pwd -P)
  L=$PBASE/layout
  mkdir -p "$L/dist" "$L/npm" "$L/tests/determinism" "$BASE/real/a/b/c/d"
  cp -R "$REPO/scripts" "$L/scripts"
  cp "$SCRIPTS_DIR/package-npm.sh" "$L/scripts/package-npm.sh"
  cp "$REPO/Cargo.toml" "$REPO/LICENSE" "$REPO/NOTICE" "$L/"
  cp "$REPO/npm/README.md" "$L/npm/README.md"
  cp -R "$REPO/tests/npm" "$L/tests/npm"
  cp -R "$REPO/tests/determinism/samples" "$REPO/tests/determinism/expected" "$L/tests/determinism/"
  cp -R "$REPO/dist/wasm" "$L/dist/wasm"
  ln -s "$BASE/real/a/b/c/d" "$BASE/tmplink" 2>/dev/null
  if [ ! -L "$BASE/tmplink" ]; then
    echo "SKIP - this shell cannot make a symlink; part 2 not run"
  else
    ( cd "$L" && env -u SCRATCH TMPDIR="$BASE/tmplink" CLI="$CLI" scripts/package-npm.sh ) > "$BASE/p2.log" 2>&1
    expect_eq "package-npm.sh with SCRATCH unset exits 0 from the layout copy" 0 "$?"
    if [ "$FAILS" -ne 0 ]; then tail -25 "$BASE/p2.log"; fi
    expect_eq "npm ls found the one installed package" 1 "$(grep -c 'npm ls --all shows exactly one package' "$BASE/p2.log")"
    expect_eq "it ends with 'npm package ok'" 1 "$(grep -c '^npm package ok: @airplanemode/glyphsift ' "$BASE/p2.log")"
    # The scratch path the script prints is the physical one: no symlink component, so resolving it changes nothing.
    CACHE_PRINTED=$(sed -n 's/.*(empty cache \(.*\)).*/\1/p' "$BASE/p2.log" | head -1)
    CACHE_PHYS=""
    [ -n "$CACHE_PRINTED" ] && [ -d "$(dirname "$CACHE_PRINTED")" ] && CACHE_PHYS=$(cd "$(dirname "$CACHE_PRINTED")" && pwd -P)/$(basename "$CACHE_PRINTED")
    expect_eq "the scratch folder it prints is a physical path" "$CACHE_PHYS" "$CACHE_PRINTED"
  fi
fi

finish
