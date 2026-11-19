#!/usr/bin/env bash
# BUG-T2-S5-14: the native determinism leg and scripts/build-wasm.sh honour CARGO_TARGET_DIR.
#
#   tests/scripts/cargo-target-dir.sh
#
# Both used to read build output from a literal `target/`, so with CARGO_TARGET_DIR set elsewhere (as CI caches and
# shared build folders do) cargo built into one place and the scripts looked in another. This test copies the sources
# to a scratch checkout that has no target/ at all, builds with CARGO_TARGET_DIR pointing into scratch, and checks:
#   - tests/determinism/run_gate_native.mjs finds the CLI under $CARGO_TARGET_DIR/release and says which one it used;
#   - scripts/build-wasm.sh takes the raw wasm from $CARGO_TARGET_DIR/wasm32-unknown-unknown/wasm and writes the package;
#   - a relative CARGO_TARGET_DIR (resolved against the repository root, as cargo does) works for the native leg.
# Needs cargo, node, wasm-bindgen (at ~/.cargo/bin or on PATH) and wasm-opt; the wasm half reports SKIP-free failure when
# a tool is missing, because the build script itself says so. No network beyond what cargo --locked needs from its cache.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/glyphsift-ctd.XXXXXX") || exit 1
SCRATCH=$(cd "$SCRATCH" && pwd -P)
cleanup() { case "$SCRATCH" in /*/glyphsift-ctd.??????) rm -rf "$SCRATCH" ;; esac; }
trap cleanup EXIT

COPY=$SCRATCH/checkout
mkdir -p "$COPY"
tar -cf - --exclude=./target --exclude=./dist --exclude=./demo/dist --exclude=./node_modules --exclude=./.git \
    --exclude=./tools --exclude=./.venv --exclude=./bench/data --exclude=./bench/results . | tar -xf - -C "$COPY"
[ -d "$COPY/target" ] && fail "the scratch checkout has no target/" || ok "the scratch checkout has no target/"

TGT=$SCRATCH/elsewhere
export CARGO_TARGET_DIR=$TGT

echo "== native leg"
( cd "$COPY" && cargo build --locked -q -p glyphsift-cli --release ) > "$SCRATCH/native-build.log" 2>&1
expect_eq "cargo build --release into CARGO_TARGET_DIR" 0 "$?"
( cd "$COPY" && node tests/determinism/run_gate_native.mjs ) > "$SCRATCH/native.log" 2>&1
expect_eq "run_gate_native.mjs passes with CARGO_TARGET_DIR set and no --cli" 0 "$?"
if grep -q '^cli: .*elsewhere[/\\]release[/\\]glyphsift' "$SCRATCH/native.log"; then ok "it names the CLI under CARGO_TARGET_DIR/release"; else fail "it names the CLI under CARGO_TARGET_DIR/release"; head -5 "$SCRATCH/native.log"; fi

# A relative CARGO_TARGET_DIR is relative to the directory cargo runs in, which is the repository root.
export CARGO_TARGET_DIR=relative-tgt
( cd "$COPY" && cargo build --locked -q -p glyphsift-cli --release ) > "$SCRATCH/native-rel-build.log" 2>&1
( cd "$COPY" && node tests/determinism/run_gate_native.mjs ) > "$SCRATCH/native-rel.log" 2>&1
expect_eq "run_gate_native.mjs passes with a relative CARGO_TARGET_DIR" 0 "$?"
unset CARGO_TARGET_DIR
export CARGO_TARGET_DIR=$TGT

echo "== wasm"
( cd "$COPY" && WASM_OUT=dist/wasm scripts/build-wasm.sh ) > "$SCRATCH/wasm.log" 2>&1
rc=$?
expect_eq "scripts/build-wasm.sh exits 0 with CARGO_TARGET_DIR set" 0 "$rc"
if [ "$rc" -ne 0 ]; then tail -6 "$SCRATCH/wasm.log"; fi
[ -f "$TGT/wasm32-unknown-unknown/wasm/glyphsift_wasm.wasm" ] && ok "cargo wrote the raw wasm under CARGO_TARGET_DIR" || fail "cargo wrote the raw wasm under CARGO_TARGET_DIR"
[ -f "$COPY/dist/wasm/web/glyphsift_bg.wasm" ] && [ -f "$COPY/dist/wasm/nodejs/glyphsift_bg.wasm" ] && ok "the web and nodejs packages were written" || fail "the web and nodejs packages were written"

# BUG-T2-S6-06: the layout-copy leg of scripts/package-npm.sh took its CLI from a literal target/release. With
# CARGO_TARGET_DIR set (and no CLI given) it built into CARGO_TARGET_DIR and then looked for the binary in target/.
echo "== npm package (CLI default honours CARGO_TARGET_DIR)"
( cd "$COPY" && env -u CLI SCRATCH="$SCRATCH/npm-scratch" scripts/package-npm.sh ) > "$SCRATCH/npm.log" 2>&1
rc=$?
expect_eq "scripts/package-npm.sh exits 0 with CARGO_TARGET_DIR set and no CLI" 0 "$rc"
if [ "$rc" -ne 0 ]; then tail -6 "$SCRATCH/npm.log"; fi
[ ! -e "$COPY/target" ] && ok "package-npm.sh made no target/ in the checkout" || fail "package-npm.sh made no target/ in the checkout"
expect_eq "it ends with 'npm package ok'" 1 "$(grep -c '^npm package ok: @airplanemode/glyphsift ' "$SCRATCH/npm.log")"

finish
