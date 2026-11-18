#!/usr/bin/env bash
# The determinism gate: the samples in tests/determinism/samples must produce byte-identical reports
# on native, Python and WASM, each compared against the checked-in bytes in tests/determinism/expected
# (which the native CLI printed). CI runs this on Linux, macOS and Windows, so passing on all also
# means the OSes agree.
set -euo pipefail
cd "$(dirname "$0")/.."

PYTHON=${PYTHON:-python3}
VENV=${VENV:-.venv}

echo "== native"
cargo build --locked -q -p glyphsift-cli --release
fail=0
for sample in tests/determinism/samples/*.txt; do
  stem=$(basename "$sample" .txt)
  if cargo run --locked -q -p glyphsift-cli --release -- check "$sample" | cmp -s - "tests/determinism/expected/$stem.json"; then
    echo "ok   $stem: native CLI matches the expected report"
  else
    echo "FAIL $stem: native CLI output differs from tests/determinism/expected/$stem.json" >&2
    fail=1
  fi
done
[ "$fail" -eq 0 ] || exit 1

# The gate call (Sprint 5, TD-42): the 200-case corpus in tests/determinism/gate is what scripts/make-gate-corpus.mjs
# generates, and the native CLI prints the recorded line for every case (an ill-formed string, which no UTF-8 file can
# hold, is fed as WTF-8 and refused with exit 1 or 2).
echo "== native: gate corpus"
node scripts/make-gate-corpus.mjs --check
node tests/determinism/run_gate_native.mjs

echo "== python"
# Python virtual environments put their executables in Scripts/ on Windows and bin/ elsewhere.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) VBIN="$VENV/Scripts" ;;
  *) if [ -d "$VENV/Scripts" ]; then VBIN="$VENV/Scripts"; else VBIN="$VENV/bin"; fi ;;
esac
if [ ! -x "$VBIN/maturin" ] && [ ! -x "$VBIN/maturin.exe" ]; then
  "$PYTHON" -m venv "$VENV"
  if [ -d "$VENV/Scripts" ]; then VBIN="$VENV/Scripts"; else VBIN="$VENV/bin"; fi
  # Version-pinned, not hash-pinned (the one known gap here): this venv builds a test-only extension
  # (maturin develop) that is never shipped, in a job that publishes nothing. The shipped wheels use
  # tools/ci/requirements.txt (hashed). Keep this version equal to the one in tools/ci/requirements.in.
  "$VBIN/pip" install --quiet maturin==1.16.0
fi
export VIRTUAL_ENV="$PWD/$VENV"
export PATH="$PWD/$VBIN:$PATH"
maturin develop --release --locked --quiet --manifest-path crates/glyphsift-py/Cargo.toml
python -I tests/determinism/run_python.py
python -I tests/determinism/run_gate_python.py

echo "== wasm"
scripts/build-wasm.sh
node tests/wasm/run_wasm_safety.mjs
node tests/determinism/run_wasm.mjs
node tests/determinism/run_gate_wasm.mjs

echo "determinism: native, python and wasm all match the expected reports and the 200 gate cases"
