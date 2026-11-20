#!/usr/bin/env bash
# Release rehearsal for glyphsift (Sprint 7, D3-02; team decisions TD-103, TD-106, TD-118, TD-123; security conditions S1-126 and S1-127).
#
#   scripts/release/rehearse.sh              build, install checks and the test-key rehearsal (the whole thing; what CI runs)
#   scripts/release/rehearse.sh all          the same
#   scripts/release/rehearse.sh proofs       only the release steps (manifest, sums, test-key signature, verification, refusal proofs) over the
#                                            files already in RELEASE_DIR (tests/scripts/rehearse.sh uses this with synthetic artefacts)
#   scripts/release/rehearse.sh assert-dir <dir>   only the check of what a release directory may hold (see assert-release-dir.mjs)
#
# This is a REHEARSAL. It signs only with the published RFC 8032 TEST 1 key, only for an id that ends in -rehearsal, and it proves that the
# same artefacts are refused without the explicit test-key flag. It publishes nothing, tags nothing, reads no secret and no real key, and
# talks to no registry. The artefacts it writes are named and uploaded as test-key rehearsal files, kept 3 days (TD-118).
#
# What `all` does, in order (a failed check stops it; nothing is skipped on any of the three operating systems except the sdist, which is
# built on Linux only, as a release would):
#   1. build the artefacts exactly as a release would: the npm tarball (scripts/build-wasm.sh, scripts/package-npm.sh), this platform's wheel
#      (maturin build --release --locked; on Linux through zig as manylinux_2_17), on Linux the sdist (scripts/package-sdist.sh) and the two
#      packaged crates (cargo package --workspace --locked, run twice: the bytes must be identical, S1-126 and TD-123);
#   2. install each BUILT artefact (never the source tree) into a fresh place and make one real call whose output is compared with committed bytes:
#      the tarball into an empty npm project (offline, a fresh cache, --ignore-scripts), the wheel into a fresh .venv (PIP_NO_INDEX=1, --no-index
#      --no-deps), on Linux a wheel built from the unpacked sdist alone with --locked, and the CLI built from the unpacked packaged .crate files
#      with glyphsift-core taken from the packaged file through a directory source (scripts/release/install-crate-offline.sh, no registry);
#   3. the dry run of every publish step (scripts/release/publish-dry-run.sh: npm publish --dry-run, cargo publish --dry-run --workspace --locked,
#      the wheel metadata check): the same commands publish.yml runs for real behind its locks; nothing is published;
#   4. the release steps: manifest, SHA256SUMS, signature with the test key, verification with the explicit flag, and the refusal proofs;
#   5. assert-dir: the directory holds only the manifest entries, the manifest and SHA256SUMS, nothing that looks like a credential or a key.
#
# Environment (all optional; each is validated):
#   RELEASE_DIR          the flat release directory (default dist-release; its last component must be dist-release)
#   RELEASE_REPORT_DIR   the report directory, a sibling and never inside RELEASE_DIR (default dist-release-report)
#   REHEARSE_ROOT        scratch root for the fresh install places (default $RUNNER_TEMP/glyphsift-rehearsal-<n>, else a fresh mktemp -d)
#   SOURCE_DATE_EPOCH    decimal seconds; default the last commit time; fixes createdAt, signedAt and the zip times (reproducible output)
#   GLYPHSIFT_TOOLS_VENV the hashed tools venv CI makes from tools/ci/requirements.txt (maturin, ziglang, uv, mypy); without it a maturin of the
#                        pinned version on PATH or `uvx maturin@<pin>` is used (the local, unhashed path)
#   PYTHON               the interpreter (default python3; python on Windows)
#   RELEASE_TOOL         a different tool path, ONLY for tests/scripts/rehearse.sh's self-tests (the pin check against VENDORED.json is then skipped)
#   REHEARSE_ALLOW_DIRTY=1  pass --allow-dirty to cargo package: local runs from a working tree with uncommitted changes only; CI never sets it
# The test-key flag is a command-line flag of the tool and is never read from any environment variable (R3).
set -euo pipefail
cd "$(dirname "$0")/../.."
REPO=$(pwd -P)
DIE_PREFIX=rehearse
# shellcheck source=scripts/release/lib-tools.sh
. scripts/release/lib-tools.sh

usage() { echo "usage: scripts/release/rehearse.sh [all|proofs|assert-dir <dir>]" >&2; exit 2; }
first_line() { head -n 1 "$1" 2>/dev/null | tr -d '\r'; }
json_get() { node -e 'let j;try{j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))}catch{process.exit(3)};const v=j[process.argv[2]];process.stdout.write(v===undefined?"":String(v))' "$(to_native "$1")" "$2"; }

CMD=${1:-all}
case "$CMD" in
  all|proofs) [ "$#" -le 1 ] || usage ;;
  assert-dir) [ "$#" -eq 2 ] || usage ;;
  *) usage ;;
esac

if [ "$CMD" = assert-dir ]; then
  D=$2
  [ -d "$D" ] || die "assert-dir: $D is not a directory"
  exec node scripts/release/assert-release-dir.mjs "$(to_native "$D")"
fi

# ---- validated paths ----------------------------------------------------------------------------------------------
guard_path() { # <variable name> <value>: non-empty, no backslash, no drive letter, no '..' segment
  case "$2" in
    ""|[A-Za-z]:*|*\\*|..|../*|*/..|*/../*) die "$1 must be a non-empty path with forward slashes only, no drive letter and no '..' segments (got '$2')" ;;
  esac
}
absolute() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$REPO" "$1" ;; esac; }
RELEASE_DIR_IN=${RELEASE_DIR:-dist-release}
REPORT_DIR_IN=${RELEASE_REPORT_DIR:-dist-release-report}
guard_path RELEASE_DIR "$RELEASE_DIR_IN"
guard_path RELEASE_REPORT_DIR "$REPORT_DIR_IN"
RELEASE_DIR=$(absolute "$RELEASE_DIR_IN")
REPORT_DIR=$(absolute "$REPORT_DIR_IN")
[ "$(basename "$RELEASE_DIR")" = dist-release ] || die "RELEASE_DIR must end in dist-release (got '$RELEASE_DIR_IN')"
[ "$(basename "$REPORT_DIR")" = dist-release-report ] || die "RELEASE_REPORT_DIR must end in dist-release-report (got '$REPORT_DIR_IN')"
case "$REPORT_DIR/" in "$RELEASE_DIR"/*) die "the report directory must not be inside the release directory" ;; esac
case "$RELEASE_DIR/" in "$REPORT_DIR"/*) die "the release directory must not be inside the report directory" ;; esac

fresh_dir() { # only the two directories this script owns are ever emptied, and only by exact name
  case "$(basename "$1")" in dist-release|dist-release-report) ;; *) die "refusing to empty '$1'" ;; esac
  [ "$1" != / ] && [ "$1" != "$REPO" ] && [ "$1" != "${HOME:-/nonexistent}" ] || die "refusing to empty '$1'"
  rm -rf "$1"
  mkdir -p "$1"
}

VERSION=$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
[ -n "$VERSION" ] || die "no workspace version in Cargo.toml"
case "$VERSION" in *[!0-9.]*|"") die "the version '$VERSION' is not a plain x.y.z (glyphsift has no pre-release identifiers)" ;; esac
PY=${PYTHON:-python3}

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  if SDE=$(git -C "$REPO" log -1 --format=%ct 2>/dev/null) && [ -n "$SDE" ]; then SOURCE_DATE_EPOCH=$SDE
  else die "SOURCE_DATE_EPOCH is not set and this checkout has no git history to take it from"; fi
fi
case "$SOURCE_DATE_EPOCH" in ""|*[!0-9]*) die "SOURCE_DATE_EPOCH must be a decimal integer (got '$SOURCE_DATE_EPOCH')" ;; esac
[ "${#SOURCE_DATE_EPOCH}" -le 12 ] || die "SOURCE_DATE_EPOCH is out of range"
export SOURCE_DATE_EPOCH

# ---- the vendored release tool ------------------------------------------------------------------------------------
TOOL_DEFAULT=$REPO/scripts/release/release-tool.mjs
TOOL=${RELEASE_TOOL:-$TOOL_DEFAULT}
[ -f "$TOOL" ] || die "release tool not found: $TOOL"
if [ "$TOOL" = "$TOOL_DEFAULT" ]; then
  WANT=$(json_get scripts/release/VENDORED.json sha256) || die "scripts/release/VENDORED.json is not readable JSON"
  GOT=$(sha256_file "$TOOL")
  [ -n "$WANT" ] && [ "$WANT" = "$GOT" ] || die "the vendored release tool's sha256 ($GOT) is not the one in scripts/release/VENDORED.json ($WANT)"
  TOOL_PIN="sha256 $GOT equals scripts/release/VENDORED.json"
else
  TOOL_PIN="RELEASE_TOOL override: the VENDORED.json pin check is skipped (self-test only)"
fi
TOOL_N=$(to_native "$TOOL")

# ---- scratch, logs and the report ---------------------------------------------------------------------------------
if [ -n "${REHEARSE_ROOT:-}" ]; then
  ROOT=$REHEARSE_ROOT
elif [ -n "${RUNNER_TEMP:-}" ]; then
  ROOT=$RUNNER_TEMP/glyphsift-rehearsal-$$
else
  ROOT=$(mktemp -d)
fi
if command -v cygpath >/dev/null 2>&1; then ROOT=$(cygpath -u "$ROOT"); fi
case "$ROOT" in /*) ;; *) die "the scratch root must be an absolute path (got '$ROOT')" ;; esac
# checked before anything is created: the artefacts are installed with no sibling repository and no source tree around them
case "$ROOT" in "$REPO"|"$REPO"/*) die "the scratch root must be outside the checkout" ;; esac
mkdir -p "$ROOT"
ROOT=$(cd "$ROOT" && pwd -P)
case "$ROOT" in "$REPO"|"$REPO"/*) die "the scratch root must be outside the checkout" ;; esac
[ -z "$(ls -A "$ROOT")" ] || die "the scratch root $ROOT is not empty"

if [ "$CMD" = all ]; then fresh_dir "$RELEASE_DIR"; else [ -d "$RELEASE_DIR" ] || die "proofs: $RELEASE_DIR does not exist"; fi
fresh_dir "$REPORT_DIR"
LOGS=$REPORT_DIR/tool-logs
mkdir -p "$LOGS"
REPORT=$REPORT_DIR/rehearsal-report.txt
note() { printf '%s\n' "$*" | tee -a "$REPORT"; }
step() { printf '\n== %s\n' "$*" | tee -a "$REPORT"; }
case "$(uname -s)" in
  Linux) OS_LABEL=linux ;;
  Darwin) OS_LABEL=macos ;;
  MINGW*|MSYS*|CYGWIN*) OS_LABEL=windows ;;
  *) OS_LABEL=other ;;
esac
{
  echo "glyphsift release rehearsal (test key, NOT A RELEASE)"
  echo "package id: glyphsift-rehearsal; version: $VERSION; operating system: $OS_LABEL ($(uname -sm))"
  echo "SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"
  echo "release tool: scripts/release/release-tool.mjs ($TOOL_PIN)"
  echo "node: $(node --version); scratch root: $ROOT"
} > "$REPORT"
cat "$REPORT"
cp Cargo.lock "$ROOT/Cargo.lock.before"

# ---- tool runners with exact expectations -----------------------------------------------------------------------------
RC=0
run_tool() { # <log name> <tool args...>: stdout and stderr to $LOGS/<name>.out and .err, the exit status in RC
  local n=$1; shift
  set +e
  node "$TOOL_N" "$@" > "$LOGS/$n.out" 2> "$LOGS/$n.err"
  RC=$?
  set -e
  note "  [$n] release-tool $* -> exit $RC; first stderr line: '$(first_line "$LOGS/$n.err")'"
}
expect_ok() { # <log name> <tool args...>: exit 0
  local n=$1; shift
  run_tool "$n" "$@"
  [ "$RC" -eq 0 ] || { sed 's/^/    | /' "$LOGS/$n.err" >&2; die "[$n] expected exit 0, got $RC"; }
}
expect_refused() { # <log name> <reason> <tool args...>: exit 3, first stderr line 'refused: <reason>', stdout {"verdict":"refused","reason":<reason>}
  local n=$1 reason=$2; shift 2
  run_tool "$n" "$@"
  [ "$RC" -eq 3 ] || die "[$n] expected exit 3 (refused), got $RC: an I/O error, a crash or a signal is not a refusal"
  [ "$(first_line "$LOGS/$n.err")" = "refused: $reason" ] || die "[$n] the first stderr line is '$(first_line "$LOGS/$n.err")', expected 'refused: $reason'"
  [ "$(json_get "$LOGS/$n.out" verdict)" = refused ] && [ "$(json_get "$LOGS/$n.out" reason)" = "$reason" ] || die "[$n] stdout is not {\"verdict\":\"refused\",\"reason\":\"$reason\"}"
  note "  ok: refused with exactly '$reason' (exit 3, first stderr line, stdout JSON)"
}
expect_usage() { # <log name> <token> <tool args...>: exit 2 and a first stderr line that starts 'usage: <token>:'
  local n=$1 tok=$2; shift 2
  run_tool "$n" "$@"
  [ "$RC" -eq 2 ] || die "[$n] expected exit 2 (usage error), got $RC"
  case "$(first_line "$LOGS/$n.err")" in "usage: $tok:"*) ;; *) die "[$n] the first stderr line is '$(first_line "$LOGS/$n.err")', expected one starting 'usage: $tok:'" ;; esac
  note "  ok: usage error 'usage: $tok:' (exit 2)"
}

# ---- the release steps and refusal proofs ---------------------------------------------------------------------------
proofs() {
  local d dn n
  if [ "$TOOL" = "$TOOL_DEFAULT" ]; then
    step "the vendored release tool gives the expected verdict on every shared vector (36 cases; the junction case runs on Windows)"
    node tests/scripts/release-tool-cases.mjs --tool "$TOOL_N" --vectors "$(to_native "$REPO/scripts/release/vectors")" | grep -E '^(FAIL|na  |release vectors)' | tee -a "$REPORT"
  fi
  step "release steps: manifest, SHA256SUMS, test-key signature (id glyphsift-rehearsal, no expiry)"
  d=$RELEASE_DIR; dn=$(to_native "$d")
  # a rerun starts from the artefacts only: the manifest and SHA256SUMS are the two files this step writes
  rm -f "$d/release-manifest.json" "$d/SHA256SUMS"
  [ -n "$(ls -A "$d")" ] || die "$d holds no artefact"
  expect_ok manifest manifest --dir "$dn" --id glyphsift-rehearsal --version "$VERSION" --licence Apache-2.0 --publisher rehearsal
  expect_ok sums sums --dir "$dn"
  expect_ok sign sign --dir "$dn" --test-key rfc8032-1
  grep -qxF 'TEST KEY SIGNATURE (RFC 8032 TEST 1, published): rehearsal only, NOT A RELEASE' "$LOGS/sign.err" || die "[sign] the test-key banner is missing from stderr"
  n=$(ls -A "$d" | grep -vxc -e release-manifest.json -e SHA256SUMS || true)
  [ "$(json_get "$d/release-manifest.json" id)" = glyphsift-rehearsal ] && [ "$(json_get "$d/release-manifest.json" version)" = "$VERSION" ] || die "the manifest's id or version is wrong"
  if node -e 'const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.exit("expiresAt" in m?1:0)' "$(to_native "$d/release-manifest.json")"; then note "  ok: the manifest has no expiresAt (TD-121)"; else die "the rehearsal manifest carries expiresAt"; fi

  step "verification with the explicit test-key flag succeeds"
  expect_ok verify-with-flag verify --dir "$dn" --expect-id glyphsift-rehearsal --trust-test-key --allow-test-key
  [ "$(json_get "$LOGS/verify-with-flag.out" verdict)" = ok ] && [ "$(json_get "$LOGS/verify-with-flag.out" id)" = glyphsift-rehearsal ] \
    && [ "$(json_get "$LOGS/verify-with-flag.out" version)" = "$VERSION" ] && [ "$(json_get "$LOGS/verify-with-flag.out" entries)" = "$n" ] \
    && [ "$(json_get "$LOGS/verify-with-flag.out" testKey)" = true ] || die "[verify-with-flag] stdout is not {verdict ok, id, version, entries $n, testKey true}"
  grep -qxF 'VERIFIED WITH THE PUBLISHED RFC 8032 TEST KEY: rehearsal only, not a release' "$LOGS/verify-with-flag.err" || die "[verify-with-flag] the test-key notice is missing from stderr"
  note "  ok: verified ($n artefacts, testKey true, the notice is on stderr)"

  step "refusal proofs: each one checks the exit code, the first stderr line and the JSON reason; an I/O error, a crash or a missing tool is never a refusal"
  # 1. the same artefacts, without the explicit flag: the test key is refused
  expect_refused refuse-no-flag test_key_refused verify --dir "$dn" --expect-id glyphsift-rehearsal --trust-test-key
  # 2. against the committed release-keys file (empty until the owner adds the real public key): nothing is trusted
  expect_refused refuse-release-keys no_trusted_key verify --dir "$dn" --expect-id glyphsift-rehearsal --trust-file "$(to_native "$REPO/docs/release-keys.json")"
  # 3. --expect-id is mandatory (R2)
  expect_usage usage-no-expect-id expect_id_required verify --dir "$dn" --trust-test-key --allow-test-key
  # 4. the allow flag with a release id is a usage error (R2)
  expect_usage usage-flag-with-release-id test_key_flag_misuse verify --dir "$dn" --expect-id glyphsift-release --trust-test-key --allow-test-key
  # 5. the test key never signs a -release id (R1): a probe manifest with the release id and a synthetic file, in the scratch root
  local probe=$ROOT/release-id-probe
  mkdir -p "$probe"
  printf 'synthetic probe, not an artefact\n' > "$probe/probe-0.0.0.tgz"
  expect_ok probe-manifest manifest --dir "$(to_native "$probe")" --id glyphsift-release --version "$VERSION" --licence Apache-2.0 --publisher release
  expect_usage usage-sign-release-id test_key_release_id sign --dir "$(to_native "$probe")" --test-key rfc8032-1
  # 6. a changed artefact is refused even with the flag: the verifier is not vacuous
  local tamper=$ROOT/tamper first
  mkdir -p "$tamper"
  cp "$d"/* "$tamper/"
  first=$(ls -A "$tamper" | grep -vxe release-manifest.json -e SHA256SUMS | head -n 1)
  node -e 'const fs=require("fs");const f=process.argv[1];const b=fs.readFileSync(f);b[Math.floor(b.length/2)]^=1;fs.writeFileSync(f,b)' "$(to_native "$tamper/$first")"
  expect_refused refuse-tampered artifact_hash_mismatch verify --dir "$(to_native "$tamper")" --expect-id glyphsift-rehearsal --trust-test-key --allow-test-key
  note "  ok: six refusal proofs"

  step "the manifest and SHA256SUMS of this run"
  note "  release-manifest.json sha256 $(sha256_file "$d/release-manifest.json")"
  note "  SHA256SUMS            sha256 $(sha256_file "$d/SHA256SUMS")"
  sed 's/^/  | /' "$d/SHA256SUMS" | tee -a "$REPORT"
  if [ "$(LC_ALL=C grep -c "$(printf '\r')" "$d/SHA256SUMS" || true)" != 0 ]; then die "SHA256SUMS contains a carriage return"; fi
}

if [ "$CMD" = proofs ]; then
  proofs
  step "assert-dir"
  node scripts/release/assert-release-dir.mjs "$(to_native "$RELEASE_DIR")" | tee -a "$REPORT"
  cmp -s Cargo.lock "$ROOT/Cargo.lock.before" || die "Cargo.lock changed"
  note "rehearsal (proofs only) ok"
  exit 0
fi

# ---- 1. build the artefacts as a release would -----------------------------------------------------------------------
# scripts/release/build-artefacts.sh is the script the build job of publish.yml runs too: the npm tarball, this platform's wheel, on Linux the
# sdist, and the two packaged crates (packaged twice, the bytes compared: S1-126, TD-123).
select_maturin
note "maturin $MATURIN_PIN from $TOOLS_FROM"
step "build: scripts/release/build-artefacts.sh (npm tarball, this platform's wheel, on Linux the sdist, the packaged crates)"
RELEASE_DIR=$RELEASE_DIR BUILD_SET=all BUILD_SCRATCH=$ROOT PYTHON=$PY scripts/release/build-artefacts.sh | tee -a "$REPORT"
WHEEL=$(ls "$RELEASE_DIR"/glyphsift-"$VERSION"-*.whl)
[ "$(printf '%s\n' "$WHEEL" | wc -l | tr -d ' ')" = 1 ] || die "expected exactly one wheel in $RELEASE_DIR"
SDIST=""
if [ "$OS_LABEL" = linux ]; then SDIST=$RELEASE_DIR/glyphsift-$VERSION.tar.gz; fi
for f in "airplanemode-glyphsift-$VERSION.tgz" "glyphsift-core-$VERSION.crate" "glyphsift-cli-$VERSION.crate"; do [ -f "$RELEASE_DIR/$f" ] || die "$f is not in $RELEASE_DIR"; done

# ---- 2. install each built artefact into a fresh place and make one real call ----------------------------------------
TESTS_N=$(to_native "$REPO/tests")
venv_python() { if [ -x "$1/.venv/Scripts/python.exe" ]; then printf '%s' "$1/.venv/Scripts/python.exe"; else printf '%s' "$1/.venv/bin/python"; fi; }
install_wheel() { # <label> <wheel file>: a fresh project with its own .venv, an install with no index, then the asserted call
  local label=$1 wheel=$2 proj=$ROOT/$1-project vp
  step "install check: $label (a fresh venv, PIP_NO_INDEX=1, pip install --no-index --no-deps)"
  mkdir -p "$proj"
  "$PY" -m venv "$(to_native "$proj/.venv")"
  vp=$(venv_python "$proj")
  PIP_NO_INDEX=1 PIP_DISABLE_PIP_VERSION_CHECK=1 "$vp" -m pip install --no-index --no-deps "$(to_native "$wheel")"
  "$vp" -I scripts/release/check-installed.py --venv "$(to_native "$proj/.venv")" --tests "$TESTS_N" --version "$VERSION" | tee -a "$REPORT"
}

step "install check: the npm tarball (an empty project, npm_config_offline=true, a fresh cache, --ignore-scripts)"
NPMP=$ROOT/npm-project
mkdir -p "$NPMP" "$ROOT/npm-cache"
( cd "$NPMP" && npm_config_offline=true npm_config_cache="$(to_native "$ROOT/npm-cache")" npm init -y > /dev/null )
( cd "$NPMP" && npm_config_offline=true npm_config_cache="$(to_native "$ROOT/npm-cache")" npm i "$(to_native "$RELEASE_DIR/airplanemode-glyphsift-$VERSION.tgz")" --ignore-scripts --offline --no-audit --no-fund )
node scripts/release/check-installed.mjs node --project "$(to_native "$NPMP")" --tests "$TESTS_N" --version "$VERSION" | tee -a "$REPORT"

install_wheel wheel "$WHEEL"

if [ -n "$SDIST" ]; then
  step "install check: a wheel built from the unpacked sdist alone with --locked (Linux), then installed into a fresh venv"
  mkdir -p "$ROOT/sdist-src" "$ROOT/sdist-wheel"
  tar -xzf "$SDIST" -C "$ROOT/sdist-src"
  (
    cd "$ROOT/sdist-src/glyphsift-$VERSION"
    "${MATURIN[@]}" build --release --locked --zig --compatibility manylinux_2_17 -o "$ROOT/sdist-wheel"
  )
  SW=$(ls "$ROOT"/sdist-wheel/glyphsift-"$VERSION"-*.whl)
  [ "$(printf '%s\n' "$SW" | wc -l | tr -d ' ')" = 1 ] || die "expected exactly one wheel built from the sdist"
  install_wheel sdist "$SW"
fi

step "install check: the CLI, built by cargo install --offline --locked from the unpacked packaged crates (glyphsift-core from the packaged file, no registry)"
scripts/release/install-crate-offline.sh "$RELEASE_DIR/glyphsift-core-$VERSION.crate" "$RELEASE_DIR/glyphsift-cli-$VERSION.crate" "$ROOT/crate-work" "$ROOT/cli" | tee -a "$REPORT"
EXE=""; [ "$OS_LABEL" = windows ] && EXE=.exe
node scripts/release/check-installed.mjs cli --cli "$(to_native "$ROOT/cli/bin/glyphsift$EXE")" --tests "$TESTS_N" --version "$VERSION" --forbid-under "$(to_native "$REPO")" | tee -a "$REPORT"

# ---- 2b. the dry run of every publish step (nothing is published) -------------------------------------------------------
step "publish dry run: nothing is published (scripts/release/publish-dry-run.sh)"
PYTHON=$PY scripts/release/publish-dry-run.sh "$RELEASE_DIR" | tee -a "$REPORT"

# ---- 3. the release steps and refusal proofs, then the directory assertion -----------------------------------------
proofs
step "assert-dir: the release directory holds only the manifest entries, release-manifest.json and SHA256SUMS"
node scripts/release/assert-release-dir.mjs "$(to_native "$RELEASE_DIR")" | tee -a "$REPORT"
cmp -s Cargo.lock "$ROOT/Cargo.lock.before" || die "Cargo.lock changed during the rehearsal"
note "Cargo.lock is unchanged"
step "done"
note "release rehearsal ok on $OS_LABEL for glyphsift $VERSION (id glyphsift-rehearsal, test key, NOT A RELEASE)"
