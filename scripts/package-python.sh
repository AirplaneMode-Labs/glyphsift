#!/usr/bin/env bash
# Build the glyphsift Python wheel (abi3, CPython >= 3.9), inspect it, install it twice into fresh
# environments (python3 -m venv + pip, and uv venv + uv pip), call it, and type-check the stubs with
# mypy --strict. It does NOT publish; a wheel for PyPI needs one build per platform (only the wheel of
# this machine is built here).
#
#   scripts/package-python.sh
#
# Environment: WHEEL_OUT (default dist/wheels, relative to the repository) is where the wheel is
# written and is emptied first; SCRATCH (default a fresh mktemp -d) holds the two venvs and the mypy
# probe; SKIP_MYPY=1 skips the mypy step (it needs `uvx mypy@<pinned>`, which may download mypy).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=${WHEEL_OUT:-dist/wheels}
case "$OUT" in
  ""|[A-Za-z]:*|*\\*|..|../*|*/..|*/../*) echo "error: WHEEL_OUT must be a non-empty path without backslashes, drive letters or '..' segments (got '$OUT')" >&2; exit 2 ;;
esac
VERSION=$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
[ -n "$VERSION" ] || { echo "error: no workspace version in Cargo.toml" >&2; exit 1; }
export PIP_DISABLE_PIP_VERSION_CHECK=1
# Builder paths (home, cargo, rustup, checkout) must not reach the wheel: remap them, then check below.
# shellcheck source=scripts/remap-paths.sh
. scripts/remap-paths.sh
# Exact tool versions (the ones the Sprint 3 evidence was produced with); bump them deliberately.
MATURIN_VERSION=1.16.0
MYPY_VERSION=2.4.1

# Only wheels are removed, and only from the output directory.
mkdir -p "$OUT"
find "$OUT" -maxdepth 1 -name 'glyphsift-*.whl' -type f -delete

echo "== tools: maturin $MATURIN_VERSION, mypy $MYPY_VERSION (pinned); uv $(uv --version)"
uvx "maturin@$MATURIN_VERSION" --version
[ "${SKIP_MYPY:-0}" = 1 ] || uvx "mypy@$MYPY_VERSION" --version
echo "== build: uvx maturin@$MATURIN_VERSION build --release (glyphsift $VERSION)"
uvx "maturin@$MATURIN_VERSION" build --release -m crates/glyphsift-py/Cargo.toml -o "$OUT"
WHEEL=$(ls "$OUT"/glyphsift-"$VERSION"-*.whl)
[ "$(echo "$WHEEL" | wc -l | tr -d ' ')" = 1 ] || { echo "error: expected exactly one wheel in $OUT" >&2; exit 1; }
case "$WHEEL" in /*) ABS=$WHEEL ;; *) ABS=$PWD/$WHEEL ;; esac
FILE=$(basename "$WHEEL")
TAG=${FILE#glyphsift-"$VERSION"-}; TAG=${TAG%.whl}
PLAT=${TAG#cp39-abi3-}
echo "wheel: $FILE ($(wc -c < "$WHEEL" | tr -d ' ') bytes)"
echo "platform tag: $PLAT (full wheel tag $TAG)"
unzip -l "$WHEEL"

echo "== static checks on the wheel"
python3 -I tests/python/check_wheel.py "$WHEEL" "$VERSION"

echo "== builder-path gate: no packed file may contain /Users/, /home/ or /private/tmp"
python3 -I scripts/check-no-builder-paths.py "$WHEEL"

SCRATCH=${SCRATCH:-$(mktemp -d)}
mkdir -p "$SCRATCH"
CALL='import glyphsift, json
assert json.loads(glyphsift.validate("नमस्ते।"))["score"]["ppm"] == 1000000
print(glyphsift.score_ppm("कखग�"))'

echo "== install 1: python3 -m venv + pip install --no-index --no-deps"
rm -rf "$SCRATCH/pipvenv"
python3 -m venv "$SCRATCH/pipvenv"
"$SCRATCH/pipvenv/bin/pip" install --no-index --no-deps "$ABS"
GOT=$("$SCRATCH/pipvenv/bin/python" -I -c "$CALL")
echo "python -I: score_ppm('कखग\\ufffd') printed $GOT (wheel $FILE, platform tag $PLAT)"
[ "$GOT" = 750000 ] || { echo "error: expected 750000" >&2; exit 1; }

echo "== install 2: uv venv + uv pip install --offline --no-index --no-deps"
rm -rf "$SCRATCH/venv"
uv venv "$SCRATCH/venv"
uv pip install --offline --no-index --no-deps --python "$SCRATCH/venv/bin/python" "$ABS"
GOT=$("$SCRATCH/venv/bin/python" -I -c "$CALL")
echo "python -I: score_ppm('कखग\\ufffd') printed $GOT (wheel $FILE, platform tag $PLAT)"
[ "$GOT" = 750000 ] || { echo "error: expected 750000" >&2; exit 1; }

echo "== both environments: the report equals the bytes the native CLI recorded, and errors are ValueError"
for py in "$SCRATCH/pipvenv/bin/python" "$SCRATCH/venv/bin/python"; do
  "$py" --version
  "$py" -I - tests/determinism/samples/01-clean-hindi.txt tests/determinism/expected/01-clean-hindi.json <<'PY'
import sys
import glyphsift

text = open(sys.argv[1], "rb").read().decode("utf-8")
want = open(sys.argv[2], "rb").read().decode("utf-8")
assert glyphsift.validate(text) + "\n" == want, "the wheel's report differs from the recorded CLI report"
assert glyphsift.clusters("नमस्ते।") == ["न", "म", "स्ते", "।"]
try:
    glyphsift.validate("a" * (4 * 1024 * 1024 + 1))
except ValueError as e:
    assert "too large" in str(e), e
else:
    raise SystemExit("input over 4 MiB did not raise ValueError")
print("ok: clean Hindi sample byte-equal to the CLI report; input over 4 MiB raises ValueError")
PY
done

if [ "${SKIP_MYPY:-0}" != 1 ]; then
  echo "== mypy --strict on a two-line script that uses the stubs"
  mkdir -p "$SCRATCH/mypy"
  printf 'import glyphsift\nn: int = glyphsift.score_ppm("x"); s: str = glyphsift.validate("x"); c: list[str] = glyphsift.clusters("x")\n' > "$SCRATCH/mypy/probe_ok.py"
  printf 'import glyphsift\nn: int = glyphsift.validate("x")\n' > "$SCRATCH/mypy/probe_bad.py"
  ( cd "$SCRATCH/mypy" && uvx "mypy@$MYPY_VERSION" --strict --python-executable "$SCRATCH/venv/bin/python" probe_ok.py )
  echo "(and the stubs are real types: a wrong annotation must fail)"
  if ( cd "$SCRATCH/mypy" && uvx "mypy@$MYPY_VERSION" --strict --python-executable "$SCRATCH/venv/bin/python" probe_bad.py ); then
    echo "error: mypy accepted 'n: int = glyphsift.validate(...)'; the stubs are not applied" >&2
    exit 1
  fi
fi
echo "python wheel ok: $FILE (platform tag $PLAT; Linux and Windows wheels are not built)"
