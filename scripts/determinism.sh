#!/usr/bin/env bash
# The determinism gate: the samples in tests/determinism/samples must produce byte-identical reports
# on native, Python and WASM, each compared against the checked-in bytes in tests/determinism/expected
# (which the native CLI printed). CI runs this on Linux, macOS and Windows (Windows configured, not
# yet executed), so passing on all also means the OSes agree.
set -euo pipefail
cd "$(dirname "$0")/.."

PYTHON=${PYTHON:-python3}
VENV=${VENV:-.venv}

echo "== native"
cargo build -q -p glyphsift-cli --release
fail=0
for sample in tests/determinism/samples/*.txt; do
  stem=$(basename "$sample" .txt)
  if cargo run -q -p glyphsift-cli --release -- check "$sample" | cmp -s - "tests/determinism/expected/$stem.json"; then
    echo "ok   $stem: native CLI matches the expected report"
  else
    echo "FAIL $stem: native CLI output differs from tests/determinism/expected/$stem.json" >&2
    fail=1
  fi
done
[ "$fail" -eq 0 ] || exit 1

echo "== python"
# Python virtual environments put their executables in Scripts/ on Windows and bin/ elsewhere.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) VBIN="$VENV/Scripts" ;;
  *) if [ -d "$VENV/Scripts" ]; then VBIN="$VENV/Scripts"; else VBIN="$VENV/bin"; fi ;;
esac
if [ ! -x "$VBIN/maturin" ] && [ ! -x "$VBIN/maturin.exe" ]; then
  "$PYTHON" -m venv "$VENV"
  if [ -d "$VENV/Scripts" ]; then VBIN="$VENV/Scripts"; else VBIN="$VENV/bin"; fi
  "$VBIN/pip" install --quiet maturin
fi
export VIRTUAL_ENV="$PWD/$VENV"
export PATH="$PWD/$VBIN:$PATH"
maturin develop --release --quiet --manifest-path crates/glyphsift-py/Cargo.toml
python -I tests/determinism/run_python.py

echo "== wasm"
scripts/build-wasm.sh
node tests/wasm/run_wasm_safety.mjs
node tests/determinism/run_wasm.mjs

echo "determinism: native, python and wasm all match the expected reports"
