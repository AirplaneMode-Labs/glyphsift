#!/usr/bin/env bash
# Build the WASM package into dist/wasm/{web,nodejs}.
#   web     -> browsers / bundlers
#   nodejs  -> used by the (Sprint 2) three-runtime determinism check
# Needs: the wasm32-unknown-unknown target (rust-toolchain.toml adds it), the `wasm-bindgen` CLI at the
# exact version pinned in crates/glyphsift-wasm/Cargo.toml, and `wasm-opt` (binaryen).
set -euo pipefail
cd "$(dirname "$0")/.."

PINNED=$(sed -n 's/^wasm-bindgen = "=\(.*\)"/\1/p' crates/glyphsift-wasm/Cargo.toml)
# ~/.cargo/bin is where `cargo install` puts the CLI; it is not always on PATH.
export PATH="$HOME/.cargo/bin:$PATH"
INSTALLED=$(wasm-bindgen --version 2>/dev/null | awk '{print $2}' || true)
if [ -z "$INSTALLED" ]; then
  echo "error: wasm-bindgen CLI not found. Install: cargo install wasm-bindgen-cli --version $PINNED --locked" >&2
  exit 1
fi
if [ "$PINNED" != "$INSTALLED" ]; then
  echo "error: wasm-bindgen CLI $INSTALLED does not match the crate pin $PINNED" >&2
  echo "       cargo install wasm-bindgen-cli --version $PINNED --locked --force" >&2
  exit 1
fi
command -v wasm-opt >/dev/null || { echo "error: wasm-opt not found (brew install binaryen / apt install binaryen)" >&2; exit 1; }

cargo build --profile wasm --target wasm32-unknown-unknown -p glyphsift-wasm
RAW=target/wasm32-unknown-unknown/wasm/glyphsift_wasm.wasm

# Post-link features rustc emits for wasm32-unknown-unknown; the profile strips the target_features
# section, so wasm-opt cannot detect them. This is also the browser baseline (bulk memory, sign
# extension, mutable globals, saturating float-to-int), identical in every engine.
WASM_FEATURES="--enable-bulk-memory-opt --enable-sign-ext --enable-mutable-globals --enable-nontrapping-float-to-int"

OUT=${WASM_OUT:-dist/wasm}
rm -rf "./$OUT"
for target in web nodejs; do
  wasm-bindgen --target "$target" --out-dir "$OUT/$target" --out-name glyphsift "$RAW"
  # shellcheck disable=SC2086
  wasm-opt -Oz $WASM_FEATURES "$OUT/$target/glyphsift_bg.wasm" -o "$OUT/$target/glyphsift_bg.wasm"
done
echo "built $OUT/web and $OUT/nodejs"
