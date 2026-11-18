#!/usr/bin/env bash
# S1-079 and the Sprint 4 additions to the CI conventions table, checked on the committed workflow files
# and scripts without the network (red-D3-02-ci.log before .github/workflows/ci.yml was changed). It does
# not replace running the workflows: it keeps the rules from drifting.
#
#  A. every `uses:` in .github/workflows/*.yml is owner/repo@<40-hex SHA> # <tag> and the (action, SHA, tag)
#     triple is a row of the conventions table below (no new action);
#  B. the packaging, demo-browser and wheels jobs contain no `pip install uv==`, `uvx `, `npm i`, `npm install`
#     or `npm init`; every `pip install` in them says --require-hashes and --only-binary=:all:; the Playwright
#     install is `npm ci --prefix tools/playwright --ignore-scripts`;
#  C. every cargo build, test, check, clippy, run, tree or install line, and every maturin build or develop
#     line, in ci.yml and in scripts/*.sh says --locked (`maturin sdist` compiles nothing and has no --locked
#     flag in 1.16.0; the wheels job checks that Cargo.lock is unchanged after it);
#  D. each actions/upload-artifact step has retention-days: 7, if-no-files-found: error and a path limited to
#     target/wheels/*.whl and target/wheels/*.tar.gz;
#  E. ci.yml has no pull_request_target, no secrets, no publish, release, registry or Pages step, and no
#     pages: write or id-token: write;
#  F. every checkout has persist-credentials: false; every job sets its own permissions;
#  G. the wheels job: matrix ubuntu, windows and macos; contents: read; manylinux_2_17 through zig on ubuntu;
#     an sdist; an install with --no-index and a smoke call.
#  H. the doc job (BUG-T2-S4-22): rustdoc warnings are errors, on the whole workspace.
#  I. fix round 1 (TD-53): the check job, on ubuntu, macos and windows with bash, runs tests/scripts/confine.test.mjs and
#     tests/scripts/release-manifest.sh (the --out containment, Windows rules included), with Node set up by the pinned
#     setup-node action.
#  J. fix round 1 (BUG-T2-S5-08): `cargo doc --workspace --no-deps --locked` prints no "output filename collision" (the CLI bin
#     is `doc = false`, so the glyphsift-py lib and the glyphsift bin no longer write the same index.html). The live run is
#     skipped, with a line saying so, only when cargo is not installed; CI_POLICY_NO_CARGO_DOC=1 skips it explicitly.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
WF=${WF:-$REPO/.github/workflows}
CI=$WF/ci.yml
[ -f "$CI" ] || { echo "error: $CI not found" >&2; exit 1; }

# job_text <file> <job>: the lines of one job under `jobs:` (jobs are the two-space-indented keys).
job_text() { awk -v job="$2" '/^jobs:/{inj=1; next} inj && /^  [A-Za-z0-9_-]+:[[:space:]]*$/{cur=$1; sub(/:$/,"",cur); on=(cur==job); next} inj && on{print}' "$1"; }
jobs_of() { awk '/^jobs:/{inj=1; next} inj && /^  [A-Za-z0-9_-]+:[[:space:]]*$/{c=$1; sub(/:$/,"",c); print c}' "$1"; }
code_lines() { grep -vE '^[[:space:]]*#' "$1"; }

# ---- A. pins ---------------------------------------------------------------------------------------
TABLE=$(cat <<'T'
actions/checkout 3d3c42e5aac5ba805825da76410c181273ba90b1 v7.0.1
actions/setup-node 949feb2413d6458794dcd2491c4babbbce0c15c1 v7.1.0
actions/setup-python 6d4fd22b20465ccc0f7354476588e8df7c9ca0e0 v7.1.0
actions/cache 55cc8345863c7cc4c66a329aec7e433d2d1c52a9 v6.1.0
actions/configure-pages 45bfe0192ca1faeb007ade9deae92b16b8254a0d v6.0.0
actions/upload-pages-artifact fc324d3547104276b827a68afc52ff2a11cc49c9 v5.0.0
actions/deploy-pages 368f82528645a54fb793d4d04e342629a3f51346 v5.0.1
dtolnay/rust-toolchain 683b588c487a69d01f6c6ddf40f036ff682cc2c8 v1
Swatinem/rust-cache d1527c8f67ef9af357290475d4af4b0fab8f12e0 v2.9.3
actions/upload-artifact cf430e030ddbb5b0abf93d22962f4752f3646cd9 v7.0.2
actions/download-artifact 9000827ccba6bdab643e8b6fd33ac0654aef8333 v8.0.2
github/codeql-action/init 33d7b85da1a04171e211befe2c739303b9a4c066 v4
github/codeql-action/analyze 33d7b85da1a04171e211befe2c739303b9a4c066 v4
github/codeql-action/upload-sarif 33d7b85da1a04171e211befe2c739303b9a4c066 v4
ossf/scorecard-action fa7117db83c52d787ae5a89f350999701505d78e v2.5.0
T
)
echo "== A. every uses: is a SHA-pinned row of the conventions table"
BADPIN=0; NUSES=0
while IFS= read -r line; do
  NUSES=$((NUSES+1))
  spec=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*(- )?uses:[[:space:]]*//')
  if [[ "$spec" =~ ^([A-Za-z0-9._/-]+)@([0-9a-f]{40})[[:space:]]+#[[:space:]]+([A-Za-z0-9._-]+)[[:space:]]*$ ]]; then
    if ! printf '%s\n' "$TABLE" | grep -qxF "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"; then
      echo "  not a table row: $spec"; BADPIN=$((BADPIN+1)); fi
  else
    echo "  not 'owner/repo@<40-hex> # <tag>': $spec"; BADPIN=$((BADPIN+1))
  fi
done < <(grep -hE '^[[:space:]]*(- )?uses:' "$WF"/*.yml)
expect_eq "all $NUSES uses: lines match the table (SHA and tag)" 0 "$BADPIN"

# ---- B. hashed, binary-only tool installs ----------------------------------------------------------
echo "== B. packaging, demo-browser and wheels install tools by hash"
for j in packaging demo-browser wheels; do
  T=$(job_text "$CI" "$j")
  if [ -z "$T" ]; then fail "job '$j' not found in ci.yml"; continue; fi
  CODE=$(printf '%s\n' "$T" | grep -vE '^[[:space:]]*#')
  expect_eq "$j: no 'pip install uv=='" 0 "$(printf '%s\n' "$CODE" | grep -cE 'pip install uv==')"
  expect_eq "$j: no 'uvx '" 0 "$(printf '%s\n' "$CODE" | grep -cE '(^|[^A-Za-z-])uvx ')"
  expect_eq "$j: no 'npm i', 'npm install' or 'npm init'" 0 "$(printf '%s\n' "$CODE" | grep -cE 'npm (i|install|init)( |$)')"
  # a tool install is hashed and binary-only; installing the wheel the job just built is `--no-index` (nothing is fetched)
  expect_eq "$j: every pip install is --require-hashes --only-binary=:all:, or --no-index" 0 "$(printf '%s\n' "$CODE" | grep -E 'pip install' | grep -vcE -- '--require-hashes.*--only-binary=:all:|--only-binary=:all:.*--require-hashes|--no-index')"
done
DB=$(job_text "$CI" demo-browser | grep -vE '^[[:space:]]*#')
expect_eq "demo-browser installs Playwright with npm ci --prefix tools/playwright --ignore-scripts" 1 "$(printf '%s\n' "$DB" | grep -cE 'npm ci --prefix tools/playwright --ignore-scripts')"
expect_eq "demo-browser points PLAYWRIGHT_DIR at tools/playwright in both browser steps" 2 "$(printf '%s\n' "$DB" | grep -cE 'PLAYWRIGHT_DIR: tools/playwright$')"
PK=$(job_text "$CI" packaging | grep -vE '^[[:space:]]*#')
expect_eq "packaging installs tools with the hashed requirements file" 1 "$(printf '%s\n' "$PK" | grep -cE 'pip install --require-hashes --no-deps --only-binary=:all: -r tools/ci/requirements.txt')"
# Sprint 5 (S1-103): the script tests now build an sdist (tests/scripts/sdist-locked.sh), so that step needs the hashed maturin too.
expect_eq "packaging hands the venv to package-python.sh and to the script tests (GLYPHSIFT_TOOLS_VENV)" 2 "$(printf '%s\n' "$PK" | grep -c 'GLYPHSIFT_TOOLS_VENV')"

# ---- C. --locked -----------------------------------------------------------------------------------
echo "== C. cargo and maturin calls say --locked"
# (a `name:` line and an echo or printf line only mention a command; the command itself is checked)
CARGO_RE='(cargo (build|test|check|clippy|run|tree|install|doc|package)( |$)|maturin (build|develop)( |$)|MATURIN\[@\]\}"? (build|develop)( |$))'
locked_misses() { code_lines "$1" | grep -E "$CARGO_RE" | grep -vE '^[[:space:]]*((- )?name:|echo |printf )' | grep -vE -- '--locked'; }
for f in "$CI" "$REPO"/scripts/build-wasm.sh "$REPO"/scripts/package-npm.sh "$REPO"/scripts/package-python.sh "$REPO"/scripts/package-sdist.sh "$REPO"/scripts/determinism.sh; do
  n=$(locked_misses "$f" | wc -l | tr -d ' ')
  expect_eq "$(basename "$f"): every cargo or maturin build, test, check, run or install line has --locked" 0 "$n"
  if [ "$n" -ne 0 ]; then locked_misses "$f" | sed 's/^/    missing --locked: /'; fi
done
expect_eq "package-python.sh builds with maturin build --release --locked" 1 "$(code_lines "$REPO/scripts/package-python.sh" | grep -cE 'MATURIN\[@\]\}" build --release --locked')"

# ---- D. upload-artifact ----------------------------------------------------------------------------
echo "== D. upload-artifact: retention-days 7, if-no-files-found error, wheel and sdist paths only"
NUP=$(code_lines "$CI" | grep -c 'actions/upload-artifact@')
expect_eq "ci.yml has at least one upload-artifact (the wheels job)" 1 "$([ "$NUP" -ge 1 ] && echo 1 || echo 0)"
expect_eq "every upload-artifact has retention-days: 7" "$NUP" "$(code_lines "$CI" | grep -c 'retention-days: 7$')"
expect_eq "every upload-artifact has if-no-files-found: error" "$NUP" "$(code_lines "$CI" | grep -c 'if-no-files-found: error$')"
PATHS=$(awk '/actions\/upload-artifact@/{u=1} u && /^[[:space:]]+path:[[:space:]]*\|[[:space:]]*$/{p=1; next} u && p && /^[[:space:]]+[a-z-]+:/{p=0; u=0} u && p && NF{gsub(/^[[:space:]]+/,""); print}' "$CI" | sort -u | tr '\n' ' ')
expect_eq "upload paths are exactly the wheels and the sdist" "target/wheels/*.tar.gz target/wheels/*.whl " "$PATHS"

# ---- E. nothing that publishes, no secrets ---------------------------------------------------------
echo "== E. no publish, release, registry or Pages step, no secrets, no pull_request_target"
for pat in 'pull_request_target' 'secrets\.' 'twine' 'npm publish' 'cargo publish' 'maturin publish' 'gh release' 'pypa/' 'softprops/' 'upload-pages-artifact' 'deploy-pages' 'configure-pages' 'pages: write' 'id-token: write' 'GITHUB_TOKEN'; do
  expect_eq "ci.yml does not contain '$pat'" 0 "$(code_lines "$CI" | grep -cE -- "$pat")"
done

# ---- F. checkout and permissions -------------------------------------------------------------------
echo "== F. persist-credentials: false after every checkout; permissions per job"
NCO=$(code_lines "$CI" | grep -c 'actions/checkout@')
expect_eq "every checkout has persist-credentials: false" "$NCO" "$(code_lines "$CI" | grep -c 'persist-credentials: false')"
NJOBS=$(jobs_of "$CI" | wc -l | tr -d ' ')
expect_eq "every job ($NJOBS) sets permissions: contents: read" "$NJOBS" "$(awk '/^jobs:/{inj=1} inj && /^    permissions:[[:space:]]*$/{getline nx; if (nx ~ /^      contents: read[[:space:]]*$/) n++} END{print n+0}' "$CI")"

# ---- G. the wheels job -----------------------------------------------------------------------------
echo "== G. wheels job"
W=$(job_text "$CI" wheels | grep -vE '^[[:space:]]*#')
if [ -z "$W" ]; then
  fail "no 'wheels' job in ci.yml"
else
  for os in ubuntu-latest windows-latest macos-latest; do expect_eq "wheels matrix has $os" 1 "$(printf '%s\n' "$W" | grep -cE "os: \[.*$os")"; done
  expect_eq "wheels: contents: read" 1 "$(printf '%s\n' "$W" | grep -cE '^      contents: read')"
  expect_eq "wheels: ubuntu builds manylinux_2_17 through zig, with --locked" 1 "$(printf '%s\n' "$W" | grep -cE 'maturin build --release --locked --zig --compatibility manylinux_2_17 -m crates/glyphsift-py/Cargo.toml')"
  expect_eq "wheels: the other platforms build with maturin build --release --locked" 1 "$(printf '%s\n' "$W" | grep -cE 'maturin build --release --locked -m crates/glyphsift-py/Cargo.toml')"
  # S1-103: the sdist comes from scripts/package-sdist.sh, which prunes the lock and builds it --locked; a bare
  # `maturin sdist` shipped a Cargo.lock the unpacked sdist could not build --locked from.
  expect_eq "wheels: the sdist is built by scripts/package-sdist.sh (S1-103)" 1 "$(printf '%s\n' "$W" | grep -cE '^[[:space:]]*scripts/package-sdist\.sh$')"
  expect_eq "wheels: no bare 'maturin sdist'" 0 "$(printf '%s\n' "$W" | grep -cE 'maturin sdist')"
  expect_eq "wheels: Cargo.lock is still checked unchanged after the sdist" 1 "$(printf '%s\n' "$W" | grep -cE 'git diff --exit-code -- Cargo.lock$')"
  expect_eq "wheels: the sdist is written to target/wheels, where the upload step looks" 1 "$(printf '%s\n' "$W" | grep -cE 'SDIST_OUT=target/wheels')"
  expect_eq "wheels: every platform's wheel goes through tests/python/check_wheel.py (stubs, licences, README wording)" 1 "$(printf '%s\n' "$W" | grep -cE 'python -I tests/python/check_wheel\.py target/wheels/')"
  expect_eq "wheels: the wheel is installed with --no-index" 1 "$(printf '%s\n' "$W" | grep -cE 'pip install --no-index --no-deps')"
  expect_eq "wheels: a smoke call checks ppm 1000000" 1 "$(printf '%s\n' "$W" | grep -c '1000000')"
fi

# ---- H. the doc job (BUG-T2-S4-22, conventions table, Sprint 5) ---------------------------------------
echo "== H. doc job: rustdoc warnings are errors"
DJ=$(job_text "$CI" doc)
if [ -z "$DJ" ]; then
  fail "no 'doc' job in ci.yml"
else
  DC=$(printf '%s\n' "$DJ" | grep -vE '^[[:space:]]*#')
  expect_eq "doc: runs on ubuntu-latest" 1 "$(printf '%s\n' "$DC" | grep -cE 'runs-on: ubuntu-latest')"
  expect_eq "doc: contents: read" 1 "$(printf '%s\n' "$DC" | grep -cE '^      contents: read')"
  expect_eq "doc: RUSTDOCFLAGS=\"-D warnings\" cargo doc --workspace --no-deps --locked" 1 "$(printf '%s\n' "$DC" | grep -cF 'RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked')"
fi

# ---- I. the containment tests run in the check job on every OS ---------------------------------------
echo "== I. check job: confine.test.mjs and release-manifest.sh on ubuntu, macos and windows (bash)"
CK=$(job_text "$CI" check)
if [ -z "$CK" ]; then
  fail "no 'check' job in ci.yml"
else
  CKC=$(printf '%s\n' "$CK" | grep -vE '^[[:space:]]*#')
  for os in ubuntu-latest macos-latest windows-latest; do expect_eq "check matrix has $os" 1 "$(printf '%s\n' "$CKC" | grep -cE "os: \[.*$os")"; done
  expect_eq "check: fail-fast is false" 1 "$(printf '%s\n' "$CKC" | grep -cE 'fail-fast: false')"
  expect_eq "check: runs node --test tests/scripts/confine.test.mjs" 1 "$(printf '%s\n' "$CKC" | grep -cE '^[[:space:]]*(run: )?node --test tests/scripts/confine\.test\.mjs$')"
  expect_eq "check: runs bash tests/scripts/release-manifest.sh" 1 "$(printf '%s\n' "$CKC" | grep -cE '^[[:space:]]*(run: )?bash tests/scripts/release-manifest\.sh$')"
  expect_eq "check: sets up Node 22 with the pinned setup-node" 1 "$(printf '%s\n' "$CK" | grep -cE 'actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7\.1\.0')"
  expect_eq "check: the workflow default shell is bash (Git Bash on windows-latest)" 1 "$(awk '/^defaults:/{d=1; next} d && /^    shell: bash[[:space:]]*$/{print "1"; exit} d && /^[a-z]/{exit}' "$CI" | head -1)"
  # the two steps are not conditional on the OS: nothing may skip them on windows-latest
  expect_eq "check: the containment steps carry no 'if:' that could skip an OS" 0 "$(printf '%s\n' "$CK" | awk '/Release-manifest --out containment/{on=1} on && /if:/{print} on && /^      - (uses|run|name):/ && !/Release-manifest --out containment/{on=0}' | grep -c .)"
fi
expect_eq "run-all.sh runs confine.test.mjs (a missing node is a failure)" 1 "$(grep -c 'confine.test.mjs' "$REPO/tests/scripts/run-all.sh" | awk '{print ($1 >= 1) ? 1 : 0}')"

# ---- J. cargo doc has no output filename collision ----------------------------------------------------
echo "== J. cargo doc prints no output filename collision (BUG-T2-S5-08)"
expect_eq "the glyphsift bin target in glyphsift-cli is doc = false" 1 "$(awk '/^\[\[bin\]\]/{b=1; next} /^\[/{b=0} b && /^doc = false[[:space:]]*$/{print "1"; exit}' "$REPO/crates/glyphsift-cli/Cargo.toml" | head -1)"
if [ "${CI_POLICY_NO_CARGO_DOC:-0}" = 1 ]; then
  echo "na   - live cargo doc: skipped on request (CI_POLICY_NO_CARGO_DOC=1); the static doc = false check above still ran"
elif ! command -v cargo >/dev/null 2>&1; then
  echo "na   - live cargo doc: not applicable here (cargo is not installed); the static doc = false check above still ran"
else
  DOCOUT=$(cd "$REPO" && RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked 2>&1); DOCRC=$?
  expect_eq "cargo doc --workspace --no-deps --locked exits 0 with -D warnings" 0 "$DOCRC"
  expect_eq "the cargo doc output contains no 'collision'" 0 "$(printf '%s\n' "$DOCOUT" | grep -ci 'collision')"
  if printf '%s\n' "$DOCOUT" | grep -qi 'collision'; then printf '%s\n' "$DOCOUT" | grep -i -B1 -A3 'collision' | head -8 | sed 's/^/    /'; fi
fi

finish
