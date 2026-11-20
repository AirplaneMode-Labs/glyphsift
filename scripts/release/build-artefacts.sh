#!/usr/bin/env bash
# Build the glyphsift release artefacts into a flat directory, exactly as a release does (Sprint 7, D3-02 and D3-03). The release rehearsal
# (scripts/release/rehearse.sh, run by CI on three operating systems) and the build job of .github/workflows/publish.yml both call this script,
# so a rehearsal builds what a release builds.
#
#   RELEASE_DIR=<an absolute path or a path relative to the repository> scripts/release/build-artefacts.sh
#
# BUILD_SET=all (default) builds, in this order: the npm tarball @airplanemode/glyphsift (scripts/build-wasm.sh, scripts/package-npm.sh); this
# platform's wheel (maturin build --release --locked, through zig as manylinux_2_17 on Linux); on Linux the sdist (scripts/package-sdist.sh,
# built --locked from its own pruned Cargo.lock); the two packaged crates glyphsift-core and glyphsift-cli (cargo package --workspace --locked,
# run twice: the bytes must be identical, S1-126 and TD-123, otherwise the script fails and the crates must leave the signed set; then twice more with
# --no-verify, which the publish job uses so that nothing is compiled where the registry tokens are: those bytes must equal the verified bytes, S1-131).
# BUILD_SET=wheel builds only this platform's wheel (the macOS and Windows legs of a release; the tarball, sdist and crates come from Linux).
# Nothing is published or signed. Environment: RELEASE_DIR (required, must exist and be empty), BUILD_SET, BUILD_SCRATCH (a fresh directory for the
# four crate runs; default a mktemp -d), GLYPHSIFT_TOOLS_VENV, PYTHON, SOURCE_DATE_EPOCH (required: it fixes the zip times of the wheel),
# REHEARSE_ALLOW_DIRTY=1 (--allow-dirty for cargo package: a local run from an uncommitted tree; CI never sets it).
set -euo pipefail
cd "$(dirname "$0")/../.."
REPO=$(pwd -P)
DIE_PREFIX=build-artefacts
# shellcheck source=scripts/release/lib-tools.sh
. scripts/release/lib-tools.sh

[ -n "${RELEASE_DIR:-}" ] || die "RELEASE_DIR is required"
case "$RELEASE_DIR" in [A-Za-z]:*|*\\*|..|../*|*/..|*/../*) die "RELEASE_DIR must use forward slashes and no '..' segments (got '$RELEASE_DIR')" ;; esac
case "$RELEASE_DIR" in /*) OUT=$RELEASE_DIR ;; *) OUT=$REPO/$RELEASE_DIR ;; esac
[ -d "$OUT" ] && [ -z "$(ls -A "$OUT")" ] || die "$OUT must exist and be empty"
BUILD_SET=${BUILD_SET:-all}
case "$BUILD_SET" in all|wheel) ;; *) die "BUILD_SET must be all or wheel (got '$BUILD_SET')" ;; esac
[ -n "${SOURCE_DATE_EPOCH:-}" ] || die "SOURCE_DATE_EPOCH is required"
case "$SOURCE_DATE_EPOCH" in *[!0-9]*) die "SOURCE_DATE_EPOCH must be a decimal integer" ;; esac
export SOURCE_DATE_EPOCH
PY=${PYTHON:-python3}
VERSION=$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
[ -n "$VERSION" ] || die "no workspace version in Cargo.toml"
case "$(uname -s)" in
  Linux) OS_LABEL=linux ;;
  Darwin) OS_LABEL=macos ;;
  MINGW*|MSYS*|CYGWIN*) OS_LABEL=windows ;;
  *) OS_LABEL=other ;;
esac
select_maturin
echo "build-artefacts: glyphsift $VERSION on $OS_LABEL, BUILD_SET=$BUILD_SET, maturin $MATURIN_PIN from $TOOLS_FROM, SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"

if [ "$BUILD_SET" = all ]; then
  echo "== build: the npm tarball"
  scripts/build-wasm.sh
  PYTHON="$PY" PACKAGE_NPM_PACK_ONLY=1 scripts/package-npm.sh
  [ -f "dist/npm/airplanemode-glyphsift-$VERSION.tgz" ] || die "dist/npm/airplanemode-glyphsift-$VERSION.tgz was not built"
  cp "dist/npm/airplanemode-glyphsift-$VERSION.tgz" "$OUT/"
fi

echo "== build: this platform's wheel (maturin build --release --locked)"
(
  . scripts/remap-paths.sh
  if [ "$OS_LABEL" = linux ]; then
    "${MATURIN[@]}" build --release --locked --zig --compatibility manylinux_2_17 -m crates/glyphsift-py/Cargo.toml -o "$(to_native "$OUT")"
  else
    "${MATURIN[@]}" build --release --locked -m crates/glyphsift-py/Cargo.toml -o "$(to_native "$OUT")"
  fi
)
WHEEL=$(ls "$OUT"/glyphsift-"$VERSION"-*.whl)
[ "$(printf '%s\n' "$WHEEL" | wc -l | tr -d ' ')" = 1 ] || die "expected exactly one wheel in $OUT"
"$PY" -I tests/python/check_wheel.py "$(to_native "$WHEEL")" "$VERSION"
"$PY" -I scripts/check-no-builder-paths.py "$(to_native "$WHEEL")"
echo "wheel: $(basename "$WHEEL")"

if [ "$BUILD_SET" = all ]; then
  if [ "$OS_LABEL" = linux ]; then
    echo "== build: the sdist (Linux only), built --locked from its own pruned Cargo.lock by scripts/package-sdist.sh"
    SDIST_OUT=$OUT scripts/package-sdist.sh
    [ -f "$OUT/glyphsift-$VERSION.tar.gz" ] || die "$OUT/glyphsift-$VERSION.tar.gz was not built"
  else
    echo "== build: no sdist on $OS_LABEL (a release builds it on Linux only)"
  fi

  echo "== build: the packaged crates, cargo package --workspace --locked, twice with the build check and twice with --no-verify (S1-126, TD-123, S1-131)"
  DIRTY=()
  if [ "${REHEARSE_ALLOW_DIRTY:-0}" = 1 ]; then DIRTY=(--allow-dirty); echo "REHEARSE_ALLOW_DIRTY=1: packaging may read uncommitted changes (a local run)"; fi
  SCRATCH=${BUILD_SCRATCH:-$(mktemp -d)}
  PKG=${CARGO_TARGET_DIR:-target}/package
  for mode in verify noverify; do
    MODE_FLAG=()
    if [ "$mode" = noverify ]; then MODE_FLAG=(--no-verify); fi
    for run in 1 2; do
      mkdir -p "$SCRATCH/crates-$mode-run$run"
      ( unset RUSTFLAGS; cargo package --workspace --locked ${DIRTY[@]+"${DIRTY[@]}"} ${MODE_FLAG[@]+"${MODE_FLAG[@]}"} )
      for c in glyphsift-core glyphsift-cli; do
        [ -f "$PKG/$c-$VERSION.crate" ] || die "packaging did not write $PKG/$c-$VERSION.crate"
        cp "$PKG/$c-$VERSION.crate" "$SCRATCH/crates-$mode-run$run/"
      done
    done
  done
  for c in glyphsift-core glyphsift-cli; do
    A=$(sha256_file "$SCRATCH/crates-verify-run1/$c-$VERSION.crate"); B=$(sha256_file "$SCRATCH/crates-verify-run2/$c-$VERSION.crate")
    C=$(sha256_file "$SCRATCH/crates-noverify-run1/$c-$VERSION.crate"); D=$(sha256_file "$SCRATCH/crates-noverify-run2/$c-$VERSION.crate")
    echo "  $c-$VERSION.crate verified run 1    sha256 $A"
    echo "  $c-$VERSION.crate verified run 2    sha256 $B"
    echo "  $c-$VERSION.crate --no-verify run 1 sha256 $C"
    echo "  $c-$VERSION.crate --no-verify run 2 sha256 $D"
    [ "$A" = "$B" ] || die "$c-$VERSION.crate differs between two cargo package --locked runs: it cannot stay in the signed set (S1-126, TD-123); the crates must leave the signed set and be published from source at the tagged commit"
    [ "$A" = "$C" ] && [ "$A" = "$D" ] || die "$c-$VERSION.crate packaged with --no-verify differs from the verified bytes (S1-131): the publish job packages with --no-verify, so the digest it compares would not be the signed one; the crates must leave the signed set"
  done
  echo "ok: two cargo package --workspace --locked runs give identical .crate bytes (S1-126)"
  echo "ok: cargo package --workspace --locked --no-verify gives the same .crate bytes as the verified run, two runs each (S1-131)"
  cp "$SCRATCH/crates-verify-run1/glyphsift-core-$VERSION.crate" "$SCRATCH/crates-verify-run1/glyphsift-cli-$VERSION.crate" "$OUT/"
fi
echo "build-artefacts: done, $(ls -A "$OUT" | wc -l | tr -d ' ') files in $OUT"
