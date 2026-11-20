# Sourced by scripts/release/build-artefacts.sh and scripts/release/rehearse.sh (it is not run). Selects maturin the one way every release
# script does, and defines the small path and hash helpers they share. The caller has done `cd <repository root>` and `set -euo pipefail`.
#
# select_maturin sets MATURIN (an array) and TOOLS_FROM: the hashed venv (GLYPHSIFT_TOOLS_VENV, what CI uses: pip install --require-hashes
# --no-deps --only-binary=:all: -r tools/ci/requirements.txt) first, else a maturin of exactly the pinned version on PATH, else
# `uvx maturin@<pin>` (the local, unhashed path; pinned by version only). With the venv, its bin or Scripts directory goes first on PATH
# so that maturin --zig finds the ziglang module of the same venv.

die() { echo "${DIE_PREFIX:-release}: $*" >&2; exit 1; }
to_native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
sha256_file() { node -e 'const c=require("crypto"),f=require("fs");process.stdout.write(c.createHash("sha256").update(f.readFileSync(process.argv[1])).digest("hex"))' "$(to_native "$1")"; }

select_maturin() {
  local pin tv
  pin=$(sed -n 's/^maturin==\(.*\)$/\1/p' tools/ci/requirements.in | head -1)
  [ -n "$pin" ] || die "tools/ci/requirements.in does not pin maturin"
  if [ -n "${GLYPHSIFT_TOOLS_VENV:-}" ]; then
    tv=$GLYPHSIFT_TOOLS_VENV
    if command -v cygpath >/dev/null 2>&1; then tv=$(cygpath -u "$tv"); fi
    if [ -d "$tv/Scripts" ]; then TOOLS_BIN=$tv/Scripts; else TOOLS_BIN=$tv/bin; fi
    [ -d "$TOOLS_BIN" ] || die "GLYPHSIFT_TOOLS_VENV ($GLYPHSIFT_TOOLS_VENV) has no bin or Scripts directory"
    TOOLS_BIN=$(cd "$TOOLS_BIN" && pwd -P)
    export PATH="$TOOLS_BIN:$PATH"
    MATURIN=("$TOOLS_BIN/maturin")
    TOOLS_FROM="the hashed venv"
  elif command -v maturin >/dev/null 2>&1 && [ "$(maturin --version)" = "maturin $pin" ]; then
    MATURIN=(maturin); TOOLS_FROM="maturin $pin on PATH"
  else
    MATURIN=(uvx "maturin@$pin"); TOOLS_FROM="uvx, pinned by version only (a local run)"
  fi
  [ "$("${MATURIN[@]}" --version)" = "maturin $pin" ] || die "maturin is not $pin"
  MATURIN_PIN=$pin
}
