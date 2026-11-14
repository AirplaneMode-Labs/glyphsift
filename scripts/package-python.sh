#!/usr/bin/env bash
# Build the glyphsift Python wheel (abi3, CPython >= 3.9), inspect it, install it twice into fresh
# environments (python3 -m venv + pip, and uv venv + uv pip), call it, and type-check the stubs with
# mypy --strict. It does NOT publish; a wheel for PyPI needs one build per platform (only the wheel of
# this machine is built here; CI's `wheels` job builds the Linux and Windows wheels and an sdist).
#
#   scripts/package-python.sh
#
# Environment: WHEEL_OUT (default dist/wheels, relative to the repository) is where the wheel is
# written and is emptied first; SCRATCH (default a fresh mktemp -d) holds the two venvs and the mypy
# probe; SKIP_MYPY=1 skips the mypy step. GLYPHSIFT_TOOLS_VENV (a venv made by
#   python -m venv V && V/bin/python -m pip install --require-hashes --no-deps --only-binary=:all: -r tools/ci/requirements.txt
# which is what CI does, S1-079) makes the script use that venv's uv, maturin and mypy and no uvx, so every tool is
# pinned by hash. Without it the tools come from `uvx maturin@<pinned>` and `uvx mypy@<pinned>`, which may
# download them (pinned by version only: the local, unhashed path).
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
# Exact tool versions: the single source is tools/ci/requirements.in (the hashed lock next to it is
# generated from it); bump them there, deliberately.
pin() { sed -n "s/^$1==\\(.*\\)\$/\\1/p" tools/ci/requirements.in | head -1; }
MATURIN_VERSION=$(pin maturin)
MYPY_VERSION=$(pin mypy)
[ -n "$MATURIN_VERSION" ] && [ -n "$MYPY_VERSION" ] || { echo "error: tools/ci/requirements.in does not pin maturin and mypy" >&2; exit 1; }
if [ -n "${GLYPHSIFT_TOOLS_VENV:-}" ]; then
  # The hashed venv: its bin directory (Scripts on Windows) first on PATH, its versions checked against the pins.
  if [ -d "$GLYPHSIFT_TOOLS_VENV/Scripts" ]; then TOOLS_BIN=$GLYPHSIFT_TOOLS_VENV/Scripts; else TOOLS_BIN=$GLYPHSIFT_TOOLS_VENV/bin; fi
  [ -d "$TOOLS_BIN" ] || { echo "error: GLYPHSIFT_TOOLS_VENV ($GLYPHSIFT_TOOLS_VENV) has no bin or Scripts directory" >&2; exit 1; }
  TOOLS_BIN=$(cd "$TOOLS_BIN" && pwd -P)
  export PATH="$TOOLS_BIN:$PATH"
  MATURIN=("$TOOLS_BIN/maturin")
  MYPY=("$TOOLS_BIN/mypy")
  UV=("$TOOLS_BIN/uv")
  TOOLS_FROM="the hashed venv $GLYPHSIFT_TOOLS_VENV"
else
  MATURIN=(uvx "maturin@$MATURIN_VERSION")
  MYPY=(uvx "mypy@$MYPY_VERSION")
  UV=(uv)
  TOOLS_FROM="uvx, pinned by version only"
fi

# Only wheels are removed, and only from the output directory.
mkdir -p "$OUT"
find "$OUT" -maxdepth 1 -name 'glyphsift-*.whl' -type f -delete

echo "== tools: maturin $MATURIN_VERSION, mypy $MYPY_VERSION (pinned, from $TOOLS_FROM); uv $("${UV[@]}" --version)"
GOT_MATURIN=$("${MATURIN[@]}" --version)
[ "$GOT_MATURIN" = "maturin $MATURIN_VERSION" ] || { echo "error: got '$GOT_MATURIN', want 'maturin $MATURIN_VERSION'" >&2; exit 1; }
if [ "${SKIP_MYPY:-0}" != 1 ]; then
  GOT_MYPY=$("${MYPY[@]}" --version)
  case "$GOT_MYPY" in "mypy $MYPY_VERSION"*) ;; *) echo "error: got '$GOT_MYPY', want 'mypy $MYPY_VERSION'" >&2; exit 1 ;; esac
fi
echo "== build: maturin build --release --locked (glyphsift $VERSION)"
"${MATURIN[@]}" build --release --locked -m crates/glyphsift-py/Cargo.toml -o "$OUT"
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
"${UV[@]}" venv "$SCRATCH/venv"
"${UV[@]}" pip install --offline --no-index --no-deps --python "$SCRATCH/venv/bin/python" "$ABS"
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
  ( cd "$SCRATCH/mypy" && "${MYPY[@]}" --strict --python-executable "$SCRATCH/venv/bin/python" probe_ok.py )
  echo "(and the stubs are real types: a wrong annotation must fail)"
  if ( cd "$SCRATCH/mypy" && "${MYPY[@]}" --strict --python-executable "$SCRATCH/venv/bin/python" probe_bad.py ); then
    echo "error: mypy accepted 'n: int = glyphsift.validate(...)'; the stubs are not applied" >&2
    exit 1
  fi
fi
echo "python wheel ok: $FILE (platform tag $PLAT; Linux and Windows wheels are built only by CI after the owner's push)"
