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
#  K. Sprint 7 (D3-02, TD-106, TD-118): the `wheels` job is folded into `release-rehearsal (<os>)` on ubuntu, macos and windows. It builds
#     the artefacts as a release would (npm tarball, wheel, on Linux the sdist and a wheel built from the unpacked sdist alone, the two
#     packaged crates), installs each built artefact into a fresh project, venv or cargo root with no sibling repo and makes one real
#     asserted call, then rehearses the release with the published RFC 8032 test key and proves the refusals. No cache of any kind,
#     contents: read, no secrets, hashed tools, --locked, and an upload of dist-release/ and dist-release-report/ only, 3 days.
#  L. Sprint 7 (D3-03, TD-105, TD-119, TD-122, TD-123): .github/workflows/publish.yml cannot fire by accident. workflow_dispatch only, no inputs, on
#     main of this repository only; the six locks (repository and ref guard, the `release` environment, vars.RELEASE_PUBLISH_ARMED, the owner's signed
#     manifest verified against docs/release-keys.json, registry credentials only as environment secrets in the step env of the publish steps,
#     RELEASE_KEY_ID equal to the one key committed), then the three bindings (tag to commit, manifest version and id, version absent from every
#     registry), then provenance, then publishing from the exact files the verified manifest lists. Nobody runs it; this test only reads it.
#  M. Sprint 7 fix round 1 (BUG-T3-S7-01 / S1-130, BUG-S1-S7-03 / S1-131, BUG-T3-S7-07, TD-125): every `npm publish` argument starts with ./ or / (a bare
#     `dir/file.tgz` is a GitHub shorthand to npm) and the dry run runs the identical string from the same layout; the crates are packaged and published with
#     --no-verify (no build in the job that holds the token), the re-package, the digest compare and `cargo publish` are adjacent steps that come before the
#     third-party PyPI action, and a post-publish crates.io sparse-index check follows; no ${{ }} in a publish.yml run: block and no ${{ matrix. }} in any run:;
#     no install from the checkout in release-rehearsal; the PyPI packages-dir is exactly the staging directory; timeouts on both publish jobs; CHECKS through
#     step env in the deny job; TD-125 (no `vars.` in a job-level if, the armed check is the first step after the checkout, the two variables are read only in
#     publish-job step env).
#  J. fix round 1 (BUG-T2-S5-08): `cargo doc --workspace --no-deps --locked` prints no "output filename collision" (the CLI bin
#     is `doc = false`, so the glyphsift-py lib and the glyphsift bin no longer write the same index.html). The live run is
#     skipped, with a line saying so, only when cargo is not installed; CI_POLICY_NO_CARGO_DOC=1 skips it explicitly.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
WF=${WF:-$REPO/.github/workflows}
# RELD: where the release scripts are read from (tests/scripts/ci-policy-mutations.sh points it at a mutated copy)
RELD=${RELD:-$REPO/scripts/release}
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
actions/attest-build-provenance 4d101475d8b20a2381f78447822ac1eab6504dd8 v4.2.2
pypa/gh-action-pypi-publish 7245906fb61fa33a13554f9d5fb856fe61758086 v1.14.3
actions/cache/restore 55cc8345863c7cc4c66a329aec7e433d2d1c52a9 v6.1.0
T
)
echo "== A. every uses: is a SHA-pinned row of the conventions table"
BADPIN=0; NUSES=0
while IFS= read -r line; do
  NUSES=$((NUSES+1))
  spec=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*(- )?uses:[[:space:]]*//')
  if [[ "$spec" =~ ^([A-Za-z0-9._/-]+)@([0-9a-f]{40})[[:space:]]+#[[:space:]]+([A-Za-z0-9._-]+)[[:space:]]*$ ]]; then
    if ! printf '%s\n' "$TABLE" | gq -xF "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"; then
      echo "  not a table row: $spec"; BADPIN=$((BADPIN+1)); fi
  else
    echo "  not 'owner/repo@<40-hex> # <tag>': $spec"; BADPIN=$((BADPIN+1))
  fi
done < <(grep -hE '^[[:space:]]*(- )?uses:' "$WF"/*.yml)
expect_eq "all $NUSES uses: lines match the table (SHA and tag)" 0 "$BADPIN"

# ---- B. hashed, binary-only tool installs ----------------------------------------------------------
echo "== B. packaging, demo-browser and release-rehearsal install tools by hash"
for j in packaging demo-browser release-rehearsal; do
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
CARGO_RE='(cargo (build|test|check|clippy|run|tree|install|doc|package|vendor|publish)( |$)|maturin (build|develop)( |$)|MATURIN\[@\]\}"? (build|develop)( |$))'
locked_misses() { code_lines "$1" | grep -E "$CARGO_RE" | grep -vE '^[[:space:]]*((- )?name:|echo |printf )' | grep -vE -- '--locked'; }
for f in "$CI" "$REPO"/scripts/build-wasm.sh "$REPO"/scripts/package-npm.sh "$REPO"/scripts/package-python.sh "$REPO"/scripts/package-sdist.sh "$REPO"/scripts/determinism.sh "$RELD"/rehearse.sh "$RELD"/install-crate-offline.sh "$RELD"/build-artefacts.sh "$RELD"/publish-dry-run.sh; do
  [ -f "$f" ] || { fail "$(basename "$f") exists (--locked rule)"; continue; }
  n=$(locked_misses "$f" | wc -l | tr -d ' ')
  expect_eq "$(basename "$f"): every cargo or maturin build, test, check, run or install line has --locked" 0 "$n"
  if [ "$n" -ne 0 ]; then locked_misses "$f" | sed 's/^/    missing --locked: /'; fi
done
expect_eq "package-python.sh builds with maturin build --release --locked" 1 "$(code_lines "$REPO/scripts/package-python.sh" | grep -cE 'MATURIN\[@\]\}" build --release --locked')"

# ---- D. upload-artifact ----------------------------------------------------------------------------
echo "== D. upload-artifact: the rehearsal upload only (dist-release/ and dist-release-report/, 3 days, test-key name, no hidden files)"
NUP=$(code_lines "$CI" | grep -c 'actions/upload-artifact@')
expect_eq "ci.yml has exactly one upload-artifact (the release-rehearsal job)" 1 "$NUP"
expect_eq "every upload-artifact has retention-days: 3 (TD-118)" "$NUP" "$(code_lines "$CI" | grep -c 'retention-days: 3$')"
expect_eq "every upload-artifact has if-no-files-found: error" "$NUP" "$(code_lines "$CI" | grep -c 'if-no-files-found: error$')"
expect_eq "every upload-artifact has include-hidden-files: false written out" "$NUP" "$(code_lines "$CI" | grep -c 'include-hidden-files: false$')"
PATHS=$(awk '/actions\/upload-artifact@/{u=1} u && /^[[:space:]]+path:[[:space:]]*\|[[:space:]]*$/{p=1; next} u && p && /^[[:space:]]+[a-z-]+:/{p=0; u=0} u && p && NF{gsub(/^[[:space:]]+/,""); print}' "$CI" | sort -u | tr '\n' ' ')
expect_eq "upload paths are exactly dist-release/ and dist-release-report/" "dist-release-report/ dist-release/ " "$PATHS"
expect_eq "the upload is named REHEARSAL-test-key-NOT-A-RELEASE-glyphsift-<os>-<sha>" 1 "$(code_lines "$CI" | grep -cF 'name: REHEARSAL-test-key-NOT-A-RELEASE-glyphsift-${{ matrix.os }}-${{ github.sha }}')"
expect_eq "no wheel or sdist upload path is left (target/wheels)" 0 "$(code_lines "$CI" | grep -c 'target/wheels/\*')"

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

# ---- G. the wheels job is folded into release-rehearsal (Sprint 7, TD-106) ----------------------------
echo "== G. no separate 'wheels' job: its platform wheels, sdist and smoke call are part of release-rehearsal (K)"
expect_eq "ci.yml has no job called 'wheels'" 0 "$(jobs_of "$CI" | grep -cx 'wheels')"
expect_eq "ci.yml has no 'wheel and sdist (' job name" 0 "$(code_lines "$CI" | grep -c 'wheel and sdist (')"

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
  if printf '%s\n' "$DOCOUT" | gq -i 'collision'; then printf '%s\n' "$DOCOUT" | grep -i -B1 -A3 'collision' | head -8 | sed 's/^/    /'; fi
fi

# ---- K. release-rehearsal (D3-02, TD-106, TD-118, S1 conditions) -----------------------------------------
echo "== K. release-rehearsal (<os>): clean-machine install checks and the test-key rehearsal"
RR=$(job_text "$CI" release-rehearsal)
if [ -z "$RR" ]; then
  fail "no 'release-rehearsal' job in ci.yml"
else
  RRC=$(printf '%s\n' "$RR" | grep -vE '^[[:space:]]*#')
  expect_eq "release-rehearsal: job name is 'release-rehearsal (\${{ matrix.os }})'" 1 "$(printf '%s\n' "$RRC" | grep -cF 'name: release-rehearsal (${{ matrix.os }})')"
  for os in ubuntu-latest macos-latest windows-latest; do expect_eq "release-rehearsal matrix has $os" 1 "$(printf '%s\n' "$RRC" | grep -cE "os: \[.*$os")"; done
  expect_eq "release-rehearsal: fail-fast is false" 1 "$(printf '%s\n' "$RRC" | grep -cE 'fail-fast: false')"
  expect_eq "release-rehearsal: permissions contents: read, and nothing else" 1 "$(printf '%s\n' "$RRC" | awk '/^    permissions:[[:space:]]*$/{getline a; getline b; if (a ~ /^      contents: read[[:space:]]*$/ && b !~ /^      [a-z-]+:/) print "1"}' | head -1)"
  expect_eq "release-rehearsal: checkout with persist-credentials: false" 1 "$(printf '%s\n' "$RRC" | grep -c 'persist-credentials: false')"
  # S1 (no caches in rehearsal jobs): no cache input, no rust-cache, no actions/cache of any spelling, no restore
  expect_eq "release-rehearsal: no 'cache:' input on any setup action" 0 "$(printf '%s\n' "$RRC" | grep -cE '^[[:space:]]+cache(-dependency-path)?:')"
  expect_eq "release-rehearsal: no Swatinem/rust-cache and no actions/cache" 0 "$(printf '%s\n' "$RRC" | grep -cE 'Swatinem/rust-cache|actions/cache')"
  expect_eq "release-rehearsal: no secrets, no GITHUB_TOKEN, no id-token, no attestations" 0 "$(printf '%s\n' "$RRC" | grep -cE 'secrets\.|GITHUB_TOKEN|id-token|attestations')"
  expect_eq "release-rehearsal: no 'inputs.' and no 'github.event.' expression" 0 "$(printf '%s\n' "$RRC" | grep -cE 'inputs\.|github\.event\.')"
  expect_eq "release-rehearsal: Rust 1.98 with the wasm32 target, from the pinned action" 1 "$(printf '%s\n' "$RR" | grep -cE 'dtolnay/rust-toolchain@683b588c487a69d01f6c6ddf40f036ff682cc2c8 # v1')"
  expect_eq "release-rehearsal: tools come from the hashed requirements file into a venv under RUNNER_TEMP" 1 "$(printf '%s\n' "$RRC" | grep -cE 'pip install --require-hashes --no-deps --only-binary=:all: -r tools/ci/requirements.txt')"
  expect_eq "release-rehearsal: the tools venv is outside the checkout (cargo package needs a clean tree)" 1 "$(printf '%s\n' "$RRC" | grep -cE 'python -m venv "\$RUNNER_TEMP/tools-venv"')"
  expect_eq "release-rehearsal: the wasm tools are the digest-pinned release binaries" 1 "$(printf '%s\n' "$RRC" | grep -cE '^[[:space:]]*run: scripts/install-wasm-tools\.sh$')"
  expect_eq "release-rehearsal: one step runs scripts/release/rehearse.sh with the hashed venv" 1 "$(printf '%s\n' "$RRC" | grep -cE '^[[:space:]]*run: scripts/release/rehearse\.sh$')"
  expect_eq "release-rehearsal: GLYPHSIFT_TOOLS_VENV points at the venv under RUNNER_TEMP (the rehearsal step and the quick-start step)" 2 "$(printf '%s\n' "$RRC" | grep -cF 'GLYPHSIFT_TOOLS_VENV: ${{ runner.temp }}/tools-venv')"
  expect_eq "release-rehearsal: a separate step asserts dist-release/ before the upload" 1 "$(printf '%s\n' "$RRC" | grep -cE '^[[:space:]]*run: scripts/release/rehearse\.sh assert-dir dist-release$')"
  expect_eq "release-rehearsal: the rehearsal runs before the assert step and the assert step before the upload" 1 "$(printf '%s\n' "$RRC" | awk '/rehearse\.sh$/{a=NR} /assert-dir/{b=NR} /upload-artifact@/{c=NR} END{print (a>0 && a<b && b<c) ? 1 : 0}')"
  expect_eq "release-rehearsal: the dry run step is not conditional (no if: on any step)" 0 "$(printf '%s\n' "$RRC" | grep -cE '^[[:space:]]+if:')"
  expect_eq "release-rehearsal: the README quick start runs on every OS, after the upload, with the hashed venv (tests/scripts/quickstart.sh)" 1 "$(printf '%s\n' "$RRC" | awk '/upload-artifact@/{u=NR} /^[[:space:]]*run: tests\/scripts\/quickstart\.sh$/{q=NR} /GLYPHSIFT_TOOLS_VENV: \$\{\{ runner\.temp \}\}\/tools-venv/{n++} END{print (u && q && u<q && n>=2) ? 1 : 0}')"
  expect_eq "release-rehearsal: PYTHON is 'python' on windows and 'python3' elsewhere (no bare python3 on Windows)" 1 "$(printf '%s\n' "$RRC" | grep -cF "PYTHON: \${{ matrix.os == 'windows-latest' && 'python' || 'python3' }}")"
  expect_eq "release-rehearsal: the workflow default shell is bash, so no step runs in cmd or powershell" 0 "$(printf '%s\n' "$RRC" | grep -cE 'shell: (cmd|powershell|pwsh)')"
fi
# the rehearsal scripts themselves
REH=$RELD/rehearse.sh
INS=$RELD/install-crate-offline.sh
for f in "$REH" "$INS"; do
  if [ -f "$f" ]; then ok "$(basename "$f") exists"; else fail "$(basename "$f") exists ($f)"; fi
done
if [ -f "$REH" ]; then
  RC=$(code_lines "$REH")
  expect_eq "rehearse.sh: set -euo pipefail" 1 "$(printf '%s\n' "$RC" | grep -cx 'set -euo pipefail')"
  expect_eq "rehearse.sh: reads no runner variable (GITHUB_*, RUNNER_OS, CI) except RUNNER_TEMP for its scratch root" 0 "$(printf '%s\n' "$RC" | grep -E 'GITHUB_|RUNNER_OS|RUNNER_ARCH|\$\{?CI[}:-]' | grep -c .)"
  expect_eq "rehearse.sh: every npm command runs with npm_config_offline=true and a fresh npm_config_cache" 0 "$(printf '%s\n' "$RC" | grep -E '[( ]npm (init|i|install) ' | grep -vE 'npm_config_offline=true .*npm_config_cache=' | grep -vE '^[[:space:]]*(step|note|echo|die) ' | grep -c .)"
  expect_eq "rehearse.sh: the npm install line has --ignore-scripts, --offline" 1 "$(printf '%s\n' "$RC" | grep -E '[( ]npm i ' | grep -- '--ignore-scripts' | grep -c -- '--offline')"
  expect_eq "rehearse.sh: every wheel install is --no-index --no-deps with PIP_NO_INDEX=1" 1 "$(printf '%s\n' "$RC" | grep -E 'PIP_NO_INDEX=1 .*pip install --no-index --no-deps' | grep -c .)"
  expect_eq "rehearse.sh: every pip install in it is --no-index" 0 "$(printf '%s\n' "$RC" | grep -E 'pip install' | grep -vc -- '--no-index')"
  expect_eq "rehearse.sh: signs with the test key only through --test-key rfc8032-1 (every --test-key is that literal)" 0 "$(printf '%s\n' "$RC" | grep -oE -- '--test-key [^ ]+' | grep -vxF -- '--test-key rfc8032-1' | grep -c .)"
  expect_eq "rehearse.sh: no key file, no --key option, no seed" 0 "$(printf '%s\n' "$RC" | grep -cE -- '--key |\.pem|\.pkcs8|seed')"
  expect_eq "rehearse.sh: no 'cargo publish' and no 'npm publish' and no twine (publishing is publish-dry-run.sh, owner-run workflow only)" 0 "$(printf '%s\n' "$RC" | grep -cE 'cargo publish|npm publish|twine|maturin publish')"
  # S1: the exact refusal tokens are asserted (exit code, first stderr line, JSON reason), and a missing tool fails the rehearsal
  for tok in 'expect_refused refuse-no-flag test_key_refused ' 'expect_refused refuse-release-keys no_trusted_key ' 'expect_refused refuse-tampered artifact_hash_mismatch ' 'expect_usage usage-sign-release-id test_key_release_id ' 'expect_usage usage-flag-with-release-id test_key_flag_misuse ' 'expect_usage usage-no-expect-id expect_id_required '; do
    expect_eq "rehearse.sh asserts the exact refusal: $tok" 1 "$(printf '%s\n' "$RC" | grep -cF -- "$tok" | awk '{print ($1 >= 1) ? 1 : 0}')"
  done
  expect_eq "rehearse.sh: a refusal is exit 3 plus 'refused: <reason>' as the first stderr line plus the JSON reason; a usage error is exit 2 plus 'usage: <token>:'" 3 "$(printf '%s\n' "$RC" | grep -cE 'expected exit 3|"refused: \$reason"|expected exit 2' )"
  expect_eq "rehearse.sh: the tool is checked to exist before anything runs (a missing tool fails)" 1 "$(printf '%s\n' "$RC" | grep -cF 'release tool not found' | awk '{print ($1 >= 1) ? 1 : 0}')"
  expect_eq "rehearse.sh: the tool's sha256 is compared with scripts/release/VENDORED.json" 1 "$(printf '%s\n' "$RC" | grep -cF 'VENDORED.json' | awk '{print ($1 >= 1) ? 1 : 0}')"
  expect_eq "rehearse.sh builds through scripts/release/build-artefacts.sh (the script the publish build job runs too)" 1 "$(printf '%s\n' "$RC" | grep -cE 'scripts/release/build-artefacts\.sh \|' | awk '{print ($1 >= 1) ? 1 : 0}')"
  BA=$RELD/build-artefacts.sh
  if [ -f "$BA" ]; then
    BC=$(code_lines "$BA")
    expect_eq "build-artefacts.sh: set -euo pipefail" 1 "$(printf '%s\n' "$BC" | grep -cx 'set -euo pipefail')"
    expect_eq "build-artefacts.sh: the crates are packaged with cargo package --workspace --locked inside a loop of two runs, and compared (S1-126, TD-123)" 1 "$(printf '%s\n' "$BC" | grep -cE 'for run in 1 2; do')"
    expect_eq "build-artefacts.sh: one cargo package --workspace --locked line" 1 "$(printf '%s\n' "$BC" | grep -cE '^[[:space:]]*\( unset RUSTFLAGS; cargo package --workspace --locked ')"
    expect_eq "build-artefacts.sh: a differing .crate fails the build (S1-126)" 1 "$(printf '%s\n' "$BC" | grep -cE '\[ "\$A" = "\$B" \] \|\| die')"
    expect_eq "build-artefacts.sh: the wheel is built with maturin build --release --locked (twice: zig on Linux, plain elsewhere)" 2 "$(printf '%s\n' "$BC" | grep -cE 'MATURIN\[@\]\}" build --release --locked ')"
    expect_eq "build-artefacts.sh: no secret, no GITHUB_ variable" 0 "$(printf '%s\n' "$BC" | grep -cE 'secrets|GITHUB_|NPM_TOKEN|CARGO_REGISTRY_TOKEN')"
  else
    fail "build-artefacts.sh exists"
  fi
  expect_eq "rehearse.sh: no sibling repository is referenced (no ../)" 0 "$(printf '%s\n' "$RC" | grep -cE '\.\./(runtime|pagetriage|localdata|dockit|site|control-plane|evidence)')"
fi
if [ -f "$INS" ]; then
  IC=$(code_lines "$INS")
  expect_eq "install-crate-offline.sh: set -euo pipefail" 1 "$(printf '%s\n' "$IC" | grep -cx 'set -euo pipefail')"
  expect_eq "install-crate-offline.sh: cargo vendor --locked" 1 "$(printf '%s\n' "$IC" | grep -cE '^cargo vendor --locked ')"
  expect_eq "install-crate-offline.sh: cargo install --offline --locked --root" 1 "$(printf '%s\n' "$IC" | grep -cE '^\( cd "\$SRC" && cargo install --path \. --offline --locked --root ')"
  expect_eq "install-crate-offline.sh: source replacement for crates-io" 1 "$(printf '%s\n' "$IC" | grep -cF 'replace-with')"
  expect_eq "install-crate-offline.sh: the packaged core's .cargo-checksum.json (package = the .crate sha256) is written by dirsource-checksum.mjs" 1 "$(printf '%s\n' "$IC" | grep -cF 'dirsource-checksum.mjs' | awk '{print ($1 >= 1) ? 1 : 0}')"
  expect_eq "install-crate-offline.sh: the log must show no registry download or index update" 1 "$(printf '%s\n' "$IC" | grep -cE 'Downloading|Downloaded|Updating' | awk '{print ($1 >= 1) ? 1 : 0}')"
fi
RK=$REPO/docs/release-keys.json
if [ -f "$RK" ]; then
  expect_eq "docs/release-keys.json is the empty release-keys file (no real key is committed)" '{"spec":"airplanemode.release-keys/0.1","keys":[]}' "$(tr -d ' \n' < "$RK")"
else
  fail "docs/release-keys.json exists"
fi
for p in 'dist-release/' 'dist-release-report/'; do
  expect_eq ".gitignore ignores $p" 1 "$(grep -cxF "/$p" "$REPO/.gitignore" | awk '{print ($1 >= 1) ? 1 : 0}')"
done
for t in maturin ziglang uv mypy; do
  expect_eq "tools/ci/requirements.txt: $t is pinned with at least one --hash=sha256 line" 1 "$(awk -v t="$t" '$0 ~ "^" t "==" {on=1; next} on && /^[A-Za-z0-9._-]+==/{on=0} on && /--hash=sha256:/{n++} END{print (n >= 1) ? 1 : 0}' "$REPO/tools/ci/requirements.txt")"
done

# ---- L. publish.yml (D3-03) --------------------------------------------------------------------------------
echo "== L. publish.yml: workflow_dispatch only, six locks, three bindings, provenance, then publish"
PUB=$WF/publish.yml
if [ ! -f "$PUB" ]; then
  fail "publish.yml exists"
else
  PC=$(code_lines "$PUB")
  # triggers
  ON_BLOCK=$(printf '%s\n' "$PC" | awk '/^on:/{on=1; next} on && /^[a-z]/{exit} on{print}')
  expect_eq "publish.yml: the only trigger is workflow_dispatch" "workflow_dispatch:" "$(printf '%s\n' "$ON_BLOCK" | sed 's/[[:space:]]*$//; s/^[[:space:]]*//' | grep -v '^$' | tr '\n' ' ' | sed 's/ $//')"
  for pat in 'pull_request' 'workflow_run' 'push:' 'schedule:' 'repository_dispatch' 'release:' 'inputs\.' 'github\.event\.' 'GITHUB_TOKEN' 'secrets\.GITHUB' 'allow-test-key' 'trust-test-key' 'rfc8032' 'test-key' 'allowTestKeys'; do
    expect_eq "publish.yml does not contain '$pat'" 0 "$(printf '%s\n' "$PC" | grep -cE -- "$pat")"
  done
  expect_eq "publish.yml: top-level permissions are empty ({})" 1 "$(printf '%s\n' "$PC" | grep -cE '^permissions: \{\}[[:space:]]*$')"
  expect_eq "publish.yml: the workflow default shell is bash (Git Bash on windows-latest)" 1 "$(printf '%s\n' "$PC" | awk '/^defaults:/{d=1; next} d && /^    shell: bash[[:space:]]*$/{print "1"; exit} d && /^[a-z]/{exit}' | head -1)"
  expect_eq "publish.yml: one concurrency group per package, never cancelled" 1 "$(printf '%s\n' "$PC" | awk '/^concurrency:/{c=1; next} c && /group: publish-glyphsift$/{g=1} c && /cancel-in-progress: false$/{k=1} END{print (g && k) ? 1 : 0}')"
  expect_eq "publish.yml has exactly the jobs build and publish" "build publish" "$(jobs_of "$PUB" | tr '\n' ' ' | sed 's/ $//')"
  BJ=$(job_text "$PUB" build | grep -vE '^[[:space:]]*#')
  PJ=$(job_text "$PUB" publish | grep -vE '^[[:space:]]*#')
  # lock 1: repository and ref guards on both jobs
  for pair in "build:$BJ" "publish:$PJ"; do
    n=${pair%%:*}; t=${pair#*:}
    expect_eq "publish.yml $n: if: github.repository == 'AirplaneMode-Labs/glyphsift' && github.ref == 'refs/heads/main'" 1 "$(printf '%s\n' "$t" | grep -cF "github.repository == 'AirplaneMode-Labs/glyphsift' && github.ref == 'refs/heads/main'")"
    expect_eq "publish.yml $n: sets its own permissions" 1 "$(printf '%s\n' "$t" | grep -cE '^    permissions:[[:space:]]*$')"
    expect_eq "publish.yml $n: checkout with persist-credentials: false" 1 "$(printf '%s\n' "$t" | grep -c 'persist-credentials: false')"
    expect_eq "publish.yml $n: no cache input and no cache action (TD-118 and the conventions table)" 0 "$(printf '%s\n' "$t" | grep -cE '^[[:space:]]+cache(-dependency-path)?:|Swatinem/rust-cache|actions/cache')"
  done
  # build job: contents: read only, no environment, no secret, no id-token
  expect_eq "publish.yml build: permissions are contents: read only" 1 "$(printf '%s\n' "$BJ" | awk '/^    permissions:[[:space:]]*$/{getline a; getline b; if (a ~ /^      contents: read[[:space:]]*$/ && b !~ /^      [a-z-]+:/) print "1"}' | head -1)"
  expect_eq "publish.yml build: no environment, no secrets, no id-token, no attestations" 0 "$(printf '%s\n' "$BJ" | grep -cE '^    environment:|secrets\.|id-token|attestations')"
  expect_eq "publish.yml build: matrix ubuntu, macos and windows, fail-fast false" 3 "$(printf '%s\n' "$BJ" | grep -cE 'os: \[ubuntu-latest, macos-latest, windows-latest\]|fail-fast: false|BUILD_SET')"
  expect_eq "publish.yml build: builds through scripts/release/build-artefacts.sh with the hashed tools" 2 "$(printf '%s\n' "$BJ" | grep -cE 'scripts/release/build-artefacts\.sh|pip install --require-hashes --no-deps --only-binary=:all: -r tools/ci/requirements.txt')"
  expect_eq "publish.yml build: one upload-artifact, 1 day, error if empty, no hidden files, named per OS" 1 "$(printf '%s\n' "$BJ" | awk '/upload-artifact@/{u=1} u && /name: glyphsift-candidate-\$\{\{ matrix.os \}\}$/{a=1} u && /retention-days: 1$/{b=1} u && /if-no-files-found: error$/{c=1} u && /include-hidden-files: false$/{d=1} u && /path: dist-release\/$/{e=1} END{print (a&&b&&c&&d&&e) ? 1 : 0}')"
  # publish job: needs build, environment release, armed, permissions
  expect_eq "publish.yml publish: needs: build" 1 "$(printf '%s\n' "$PJ" | grep -cE '^    needs: build[[:space:]]*$')"
  expect_eq "publish.yml publish: environment: release (lock 2)" 1 "$(printf '%s\n' "$PJ" | grep -cE '^    environment: release[[:space:]]*$')"
  # lock 3 is a step, not a job-level if: an environment's variables are not visible in a job's `if` (the environment is resolved after it), so a job-level test would
  # silently skip the job whenever the owner sets the variable where the plan says to (on the release environment). In a step it sees repository and environment variables.
  expect_eq "publish.yml publish: lock 3 is the first step after the checkout, RELEASE_PUBLISH_ARMED from vars, checked by publish-guard.sh armed" 1 "$(printf '%s\n' "$PJ" | awk '/^      - name: Lock 3, /{f=NR} /RELEASE_PUBLISH_ARMED: \$\{\{ vars\.RELEASE_PUBLISH_ARMED \}\}/{v=NR} /publish-guard\.sh armed/{a=NR} /publish-guard\.sh key-id/{k=NR} /npm publish |attest-build-provenance@|gh-action-pypi-publish@|cargo publish --workspace/{p=(p?p:NR)} END{print (f && v && a && k && p && f<v && v<a && a<k && a<p) ? 1 : 0}')"
  expect_eq "publish.yml publish: the job-level if holds only the repository and ref guards (no vars. there)" 0 "$(printf '%s\n' "$PJ" | grep -E '^    if:' | grep -c 'vars\.')"
  expect_eq "publish.yml publish: permissions are contents: read, id-token: write, attestations: write" 1 "$(printf '%s\n' "$PJ" | awk '/^    permissions:[[:space:]]*$/{getline a; getline b; getline c; getline d; if (a ~ /contents: read/ && b ~ /id-token: write/ && c ~ /attestations: write/ && d !~ /^      [a-z-]+:/) print "1"}' | head -1)"
  expect_eq "publish.yml: id-token and attestations appear only in the publish job" 0 "$(printf '%s\n' "$PC" | grep -cE 'id-token|attestations: write' | awk -v p="$(printf '%s\n' "$PJ" | grep -cE 'id-token|attestations: write')" '{print $1 - p}')"
  # lock 5: secrets only as NPM_TOKEN and CARGO_REGISTRY_TOKEN, in a step env of the publish job
  expect_eq "publish.yml: 'secrets.' appears exactly twice, NPM_TOKEN and CARGO_REGISTRY_TOKEN" "NPM_TOKEN CARGO_REGISTRY_TOKEN" "$(printf '%s\n' "$PC" | grep -oE 'secrets\.[A-Z_]+' | sed 's/secrets\.//' | tr '\n' ' ' | sed 's/ $//')"
  expect_eq "publish.yml: both secrets are in the publish job" 2 "$(printf '%s\n' "$PJ" | grep -cE '^[[:space:]]+[A-Z_]+: \$\{\{ secrets\.(NPM_TOKEN|CARGO_REGISTRY_TOKEN) \}\}[[:space:]]*$')"
  expect_eq "publish.yml: NODE_AUTH_TOKEN is the npm step's variable and CARGO_REGISTRY_TOKEN the cargo step's, never a workflow-level env" 0 "$(printf '%s\n' "$PC" | awk '/^env:/{e=1; next} e && /^[a-z]/{e=0} e{print}' | grep -c 'secrets')"
  # the owner's signed manifest, verified against the committed release keys (lock 4), with the exact expected id
  expect_eq "publish.yml publish: the signed manifest comes from the GitHub release (gh release download)" 1 "$(printf '%s\n' "$PJ" | grep -cE 'gh release download "v\$VERSION" ')"
  expect_eq "publish.yml publish: release-tool verify with --trust-file docs/release-keys.json and --expect-id glyphsift-release" 1 "$(printf '%s\n' "$PJ" | grep -cE 'release-tool\.mjs verify --dir .* --expect-id glyphsift-release --trust-file docs/release-keys\.json')"
  # lock 6 and the three bindings go through scripts/release/publish-guard.sh
  for g in 'publish-guard.sh key-id' 'publish-guard.sh tag-binding' 'publish-guard.sh manifest-binding' 'publish-guard.sh registry-absent' 'publish-guard.sh exact-set'; do
    expect_eq "publish.yml publish: runs $g" 1 "$(printf '%s\n' "$PJ" | grep -cF "scripts/release/$g")"
  done
  expect_eq "publish.yml publish: RELEASE_KEY_ID comes from the environment's variables" 1 "$(printf '%s\n' "$PJ" | grep -cF 'RELEASE_KEY_ID: ${{ vars.RELEASE_KEY_ID }}')"
  expect_eq "publish.yml publish: the download is from this run only (no run-id, no github-token input)" 0 "$(printf '%s\n' "$PJ" | grep -cE 'run-id:|github-token:')"
  expect_eq "publish.yml publish: download-artifact merges the candidates into one directory" 1 "$(printf '%s\n' "$PJ" | grep -cE 'merge-multiple: true')"
  # order: guards, then verify, then provenance, then the publish steps
  ORDER=$(printf '%s\n' "$PJ" | awk '
    /publish-guard\.sh key-id/{k=NR} /publish-guard\.sh tag-binding/{t=NR} /publish-guard\.sh manifest-binding/{m=NR} /publish-guard\.sh registry-absent/{r=NR} /publish-guard\.sh exact-set/{x=NR}
    /release-tool\.mjs verify/{v=NR} /attest-build-provenance@/{a=NR}
    /npm publish /{n=NR} /gh-action-pypi-publish@/{p=NR} /^[[:space:]]*(run: )?cargo publish --workspace --locked/{c=NR}
    END{ok=(k && t && m && r && x && v && a && n && p && c); if (ok && k<a && t<a && m<a && r<a && x<a && v<a && a<n && a<p && a<c && v<n && v<p && v<c) print "1"; else print "0"}')
  expect_eq "publish.yml publish: key-id, tag, manifest, registry and exact-set checks and the verify come before provenance, and provenance before every publish step" 1 "$ORDER"
  expect_eq "publish.yml publish: provenance is actions/attest-build-provenance (v4.2.2) on the exact verified paths" 1 "$(printf '%s\n' "$PJ" | grep -cE 'actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8 # v4.2.2')"
  expect_eq "publish.yml publish: npm publish carries --provenance --access public --ignore-scripts and a derived --tag" 1 "$(printf '%s\n' "$PJ" | grep -E '^[[:space:]]*npm publish ' | grep -- '--provenance' | grep -- '--access public' | grep -- '--ignore-scripts' | grep -c -- '--tag "\$DIST_TAG"')"
  expect_eq "publish.yml publish: the dist-tag is derived in shell by publish-guard.sh dist-tag" 1 "$(printf '%s\n' "$PJ" | grep -cF 'publish-guard.sh dist-tag')"
  expect_eq "publish.yml publish: PyPI uses the pinned action with attestations: true written out" 1 "$(printf '%s\n' "$PJ" | awk '/gh-action-pypi-publish@7245906fb61fa33a13554f9d5fb856fe61758086 # v1.14.3/{u=1} u && /attestations: true/{print "1"; exit}')"
  expect_eq "publish.yml publish: crates are published as a workspace, locked, after the digests of the re-packaged crates are compared" 1 "$(printf '%s\n' "$PJ" | awk '/publish-guard\.sh crate-digests/{d=NR} /^[[:space:]]*(run: )?cargo publish --workspace --locked/{c=NR} END{print (d && c && d<c) ? 1 : 0}')"
  expect_eq "publish.yml publish: publish steps name no glob (no '*' in an npm publish, cargo publish or upload path)" 0 "$(printf '%s\n' "$PJ" | grep -E 'npm publish |cargo publish|packages-dir|subject-path' | grep -c '\*')"
  expect_eq "publish.yml: the npm token is passed as NODE_AUTH_TOKEN from secrets.NPM_TOKEN only" 1 "$(printf '%s\n' "$PJ" | grep -cF 'NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}')"
fi
# the guard script and the dry-run script
GUARD=$RELD/publish-guard.sh
DRY=$RELD/publish-dry-run.sh
for f in "$GUARD" "$DRY"; do
  if [ -f "$f" ]; then ok "$(basename "$f") exists"; else fail "$(basename "$f") exists"; fi
done
if [ -f "$GUARD" ]; then
  GC=$(code_lines "$GUARD")
  expect_eq "publish-guard.sh: set -euo pipefail" 1 "$(printf '%s\n' "$GC" | grep -cx 'set -euo pipefail')"
  expect_eq "publish-guard.sh: reads no runner variable (GITHUB_*, RUNNER_*): the workflow passes GUARD_* values in" 0 "$(printf '%s\n' "$GC" | grep -cE 'GITHUB_|RUNNER_')"
  expect_eq "publish-guard.sh: registry lookups fail closed (only a 404 passes) over https with TLS 1.2" 1 "$(printf '%s\n' "$GC" | grep -cE -- "--proto '=https' --tlsv1.2" | awk '{print ($1 >= 1) ? 1 : 0}')"
fi
if [ -f "$DRY" ]; then
  DC=$(code_lines "$DRY")
  expect_eq "publish-dry-run.sh: set -euo pipefail" 1 "$(printf '%s\n' "$DC" | grep -cx 'set -euo pipefail')"
  expect_eq "publish-dry-run.sh: cargo publish --dry-run --workspace --locked" 1 "$(printf '%s\n' "$DC" | grep -cE '^CARGO_OUT=.*cargo publish --dry-run --workspace --locked ')"
  expect_eq "publish-dry-run.sh: npm publish --dry-run" 1 "$(printf '%s\n' "$DC" | grep -cE '^NPM_OUT=\$\( cd "\$LAYOUT" && npm publish .*--dry-run ')"
  expect_eq "publish-dry-run.sh: every publish line is a dry run" 0 "$(printf '%s\n' "$DC" | grep -E '(npm|cargo|twine|maturin) publish' | grep -vcE -- '--dry-run|^[[:space:]]*(echo|printf|note|die) ')"
  expect_eq "publish-dry-run.sh: no secret, no token, no login" 0 "$(printf '%s\n' "$DC" | grep -cE 'secrets|TOKEN|npm login|cargo login|\.npmrc|\.pypirc')"
fi
expect_eq "rehearse.sh runs scripts/release/publish-dry-run.sh (the dry-run script is the one CI's rehearsal runs)" 1 "$(code_lines "$RELD/rehearse.sh" | grep -cE 'scripts/release/publish-dry-run\.sh ' | awk '{print ($1 >= 1) ? 1 : 0}')"
# every workflow: no pull_request_target, no workflow_run, 'secrets.' only in publish.yml
for f in "$WF"/*.yml; do
  b=$(basename "$f")
  expect_eq "$b: no pull_request_target and no workflow_run" 0 "$(code_lines "$f" | grep -cE 'pull_request_target|workflow_run')"
  if [ "$b" != publish.yml ]; then expect_eq "$b: no 'secrets.' (only publish.yml has NPM_TOKEN and CARGO_REGISTRY_TOKEN)" 0 "$(code_lines "$f" | grep -cE 'secrets\.')"; fi
done
IDT=0
for f in "$WF"/*.yml; do
  b=$(basename "$f")
  if [ "$b" = publish.yml ] || [ "$b" = pages.yml ]; then continue; fi
  IDT=$((IDT + $(code_lines "$f" | grep -cE 'id-token|attestations: write')))
done
expect_eq "no workflow other than publish.yml and pages.yml has id-token or attestations" 0 "$IDT"


# ---- M. Sprint 7 fix round 1 -------------------------------------------------------------------------------------
echo "== M. FR1: npm path form, crates without a build, run: blocks, timeouts, TD-125"
# run_exprs <file>: the lines of every run: step (a single line or a block scalar) that hold a ${{ }} expression, as "<line>: <text>"
RUN_EXPRS_AWK='
function indent(s) { match(s, /^ */); return RLENGTH }
{
  line = $0
  if (inrun) {
    if (line ~ /^[[:space:]]*$/) next
    if (indent(line) > runind) { if (line ~ /\$\{\{/) print NR ": " line; next }
    inrun = 0
  }
  if (line ~ /^[[:space:]]*(- )?run:/) {
    runind = indent(line); if (line ~ /^[[:space:]]*- /) runind += 2
    rest = line; sub(/^[[:space:]]*(- )?run:[[:space:]]*/, "", rest)
    if (rest ~ /^[|>][-+]?[[:space:]]*$/) { inrun = 1; next }
    if (rest ~ /\$\{\{/) print NR ": " line
  }
}'
run_exprs() { awk "$RUN_EXPRS_AWK" "$1"; }
# step_of <job text> <regex>: the number of the step (1-based, counted by the `      - ` lines) of the first line matching the regex, or 0
step_of() { printf '%s\n' "$1" | awk -v re="$2" '/^      - /{n++} $0 ~ re {print n+0; f=1; exit} END{if (!f) print 0}'; }
# step_text <job text> <n>: the lines of step n
step_text() { printf '%s\n' "$1" | awk -v n="$2" '/^      - /{k++} k==n'; }

# npm_arg: stdin lines to the first argument after the first `npm publish ` on the first line that has one (a "quoted" argument is kept with its quotes)
npm_arg() { awk '{ i = index($0, "npm publish "); if (i == 0) next; r = substr($0, i + 12); sub(/^ +/, "", r); if (substr(r, 1, 1) == "\"") { j = index(substr(r, 2), "\""); print substr(r, 1, j + 1) } else { split(r, a, " "); print a[1] } exit }'; }
# M1. BUG-T3-S7-01 / S1-130: npm reads `dir/file.tgz` as the GitHub shorthand user/repo, so every npm publish argument must start with ./ or /
NPMBAD=0; NPMN=0
for f in "$WF"/*.yml; do
  while IFS= read -r line; do
    NPMN=$((NPMN+1))
    arg=$(printf '%s\n' "$line" | npm_arg)
    arg=${arg#\"}
    case "$arg" in ./*|/*) ;; *) echo "  npm publish argument is not a ./ or / path: $line"; NPMBAD=$((NPMBAD+1)) ;; esac
  done < <(code_lines "$f" | grep -E 'npm publish' | grep -vE '^[[:space:]]*((- )?name:|echo |printf )')
done
expect_eq "every npm publish argument in every workflow starts with ./ or / ($NPMN found)" 0 "$NPMBAD"
expect_eq "there is exactly one npm publish line in the workflows (publish.yml)" 1 "$NPMN"
ARG_WF=$(code_lines "$PUB" | grep -E '^[[:space:]]*(run: )?npm publish ' | npm_arg)
ARG_DRY=$(code_lines "$DRY" | grep -E 'npm publish "' | grep -vE '^[[:space:]]*(echo|printf|note|die) ' | npm_arg)
expect_eq "publish.yml's npm publish argument is \"./verified/\$(cat lists/npm.txt)\"" '"./verified/$(cat lists/npm.txt)"' "$ARG_WF"
expect_eq "the dry run's npm publish argument is character for character the workflow's" "$ARG_WF" "$ARG_DRY"
expect_eq "the dry run runs npm publish from a directory laid out like the workflow's (verified/ and lists/npm.txt under the working directory)" 1 "$(code_lines "$DRY" | grep -cE '^NPM_OUT=\$\( cd "\$LAYOUT" && npm publish "\./verified/\$\(cat lists/npm\.txt\)" ')"
expect_eq "the dry run builds that layout (verified/ with the tarball, lists/npm.txt with its name)" 3 "$(code_lines "$DRY" | grep -cE 'mkdir "\$LAYOUT/verified" "\$LAYOUT/lists"|cp "\$TGZ" "\$LAYOUT/verified/"|> "\$LAYOUT/lists/npm\.txt"')"
expect_eq "the dry run's npm publish is --dry-run (and has no --provenance: that needs the workflow's OIDC token)" 1 "$(code_lines "$DRY" | grep -E '^NPM_OUT=' | grep -- '--dry-run' | grep -vc -- '--provenance')"

# M2. BUG-T3-S7-07: no ${{ }} in a publish.yml run: block, and no ${{ matrix. }} in any run: of any workflow
expect_eq "publish.yml: no \${{ }} expression inside any run: step (values reach a script only through step env)" 0 "$(run_exprs "$PUB" | wc -l | tr -d ' ')"
MATRIXRUN=0
for f in "$WF"/*.yml; do MATRIXRUN=$((MATRIXRUN + $(run_exprs "$f" | grep -c '\${{ *matrix\.'))); done
expect_eq "no workflow interpolates \${{ matrix.* }} inside a run: step (it goes through step env and is validated)" 0 "$MATRIXRUN"
DENY=$(job_text "$CI" deny)
if [ -z "$DENY" ]; then fail "no 'deny' job in ci.yml"; else
  DENYC=$(printf '%s\n' "$DENY" | grep -vE '^[[:space:]]*#')
  expect_eq "deny: the matrix value reaches the script as CHECKS through step env" 1 "$(printf '%s\n' "$DENYC" | grep -cE '^[[:space:]]+CHECKS: \$\{\{ matrix\.checks \}\}[[:space:]]*$')"
  expect_eq "deny: the script validates CHECKS against the two fixed values, and refuses anything else, before using it" 1 "$(printf '%s\n' "$DENYC" | awk '/case "\$CHECKS" in/{c=NR} /advisories\|"bans licenses sources"\)/{a=NR} /^[[:space:]]*\*\).*exit 1/{d=NR} /cargo-deny" --all-features check \$CHECKS/{r=NR} END{print (c && a && d && r && c<a && a<d && d<r) ? 1 : 0}')"
  expect_eq "deny: cargo-deny is run on \$CHECKS, not on an expression" 1 "$(printf '%s\n' "$DENYC" | grep -cF 'cargo-deny" --all-features check $CHECKS')"
fi

# M3. BUG-T3-S7-07: timeouts on both publish jobs (pagetriage's values are the reference: 75 for the three-OS build, 30 for the publish job)
for pair in "build:75" "publish:30"; do
  j=${pair%%:*}; want=${pair#*:}
  expect_eq "publish.yml $j: timeout-minutes: $want" "$want" "$(job_text "$PUB" "$j" | grep -vE '^[[:space:]]*#' | sed -nE 's/^    timeout-minutes: ([0-9]+)[[:space:]]*$/\1/p' | head -1)"
done

# M4. BUG-T3-S7-07 (a): nothing in release-rehearsal or publish.yml installs from the checkout (the CLI is built from the unpacked packaged .crate by install-crate-offline.sh)
INSTALL_RE='cargo install|cargo binstall|pip install +(-e|--editable|\.|\./|\.\.)|pip install .*( \./| \.\./| file:)|npm (i|install|link|ln)( +-[A-Za-z-]+)* +(\.|\./|\.\./|file:)|maturin develop'
RRM=$(job_text "$CI" release-rehearsal | grep -vE '^[[:space:]]*#')
expect_eq "release-rehearsal: no install from the checkout (no cargo install, pip install -e or ., npm install ., maturin develop)" 0 "$(printf '%s\n' "$RRM" | grep -cE "$INSTALL_RE")"
expect_eq "publish.yml: no install from the checkout" 0 "$(printf '%s\n' "$PC" | grep -cE "$INSTALL_RE")"
expect_eq "the only script in scripts/release that runs cargo install is install-crate-offline.sh (inside the unpacked packaged crate)" "install-crate-offline.sh" "$(for f in "$RELD"/*.sh; do if code_lines "$f" | grep -vE '^[[:space:]]*(step|note|echo|printf|die) ' | gq -E 'cargo install'; then basename "$f"; fi; done | tr '\n' ' ' | sed 's/ $//')"
expect_eq "rehearse.sh and build-artefacts.sh do not install from the checkout" 0 "$( { code_lines "$RELD/rehearse.sh"; code_lines "$RELD/build-artefacts.sh"; } | grep -vE '^[[:space:]]*(step|note|echo|printf|die) ' | grep -cE 'cargo install|pip install +(-e|\.)|maturin develop')"

# M5. BUG-T3-S7-07 (c): the PyPI step uploads from exactly the staging directory, which holds exactly the files listed in the verified manifest
PKGDIRS=$(printf '%s\n' "$PC" | grep -E '^[[:space:]]*packages-dir:' | sed -E 's/^[[:space:]]*packages-dir:[[:space:]]*//' | tr '\n' ' ')
expect_eq "publish.yml: the one packages-dir is exactly pypi-dist/ (the staging directory), never verified/ or any other" "pypi-dist/ " "$PKGDIRS"
expect_eq "publish.yml: the staging step makes pypi-dist with a plain mkdir (it fails if the directory exists), copies each name of lists/pypi.txt from verified/, and checks the count" 3 "$(printf '%s\n' "$PJ" | grep -cE '^[[:space:]]*mkdir pypi-dist[[:space:]]*$|cp "verified/\$f" "pypi-dist/\$f"|test "\$\(ls -A pypi-dist \| wc -l \| tr -d . .\)" = "\$\(wc -l < lists/pypi\.txt \| tr -d . .\)"')"
expect_eq "publish.yml: the step right before the PyPI step is the staging step" 1 "$(printf '%s\n' "$PJ" | awk '/^      - /{n++; if ($0 ~ /Stage exactly the PyPI files/) st=n; if ($0 ~ /gh-action-pypi-publish@/) py=n} END{print (st && py && st+1==py) ? 1 : 0}')"

# M6. TD-125: no vars. in any job-level if; the armed check is the first step after the checkout; the two variables are read once each, in publish-job step env
VARSIF=0
for f in "$WF"/*.yml; do VARSIF=$((VARSIF + $(code_lines "$f" | grep -E '^    if:' | grep -c 'vars\.'))); done
expect_eq "no workflow has vars. in a job-level if (an environment's variables are not visible there)" 0 "$VARSIF"
expect_eq "publish.yml: vars. appears exactly twice, RELEASE_PUBLISH_ARMED and RELEASE_KEY_ID" "RELEASE_PUBLISH_ARMED RELEASE_KEY_ID" "$(printf '%s\n' "$PC" | grep -oE 'vars\.[A-Z_]+' | sed 's/vars\.//' | tr '\n' ' ' | sed 's/ $//')"
expect_eq "publish.yml: both variables are read in step env of the publish job (ten-space env keys), never in job-level env" 2 "$(printf '%s\n' "$PJ" | grep -cE '^          RELEASE_(PUBLISH_ARMED|KEY_ID): \$\{\{ vars\.RELEASE_(PUBLISH_ARMED|KEY_ID) \}\}[[:space:]]*$')"
expect_eq "publish.yml publish: step 1 is the checkout and step 2 is lock 3 (armed): nothing else runs before the armed check" "1 2" "$(printf '%s\n' "$PJ" | awk '/^      - /{n++; if (n==1 && $0 ~ /actions\/checkout@/) a=1; if (n==2 && $0 ~ /name: Lock 3, RELEASE_PUBLISH_ARMED is true/) b=2} END{printf "%s %s\n", a+0, b+0}')"
expect_eq "publish.yml publish: lock 6 (key id) comes before the third-party rust-toolchain action and before every publishing step" 1 "$( L6=$(step_of "$PJ" 'name: Lock 6, '); RT=$(step_of "$PJ" 'dtolnay/rust-toolchain@'); [ "$L6" -gt 2 ] && [ "$RT" -gt "$L6" ] && echo 1 || echo 0)"
expect_eq "publish.yml publish: step 2 runs publish-guard.sh armed" 1 "$(step_text "$PJ" 2 | grep -c 'scripts/release/publish-guard\.sh armed')"

# M7. BUG-S1-S7-03 / S1-131: crates without a build in the token-holding job, re-package + digest compare + publish adjacent and before the PyPI action, then the index check
expect_eq "publish.yml: exactly one cargo package line, and it is cargo package --workspace --locked --no-verify" "1 1" "$(printf '%s\n' "$PJ" | grep -cE 'cargo package') $(printf '%s\n' "$PJ" | grep -cE '^[[:space:]]*cargo package --workspace --locked --no-verify[[:space:]]*$')"
expect_eq "publish.yml: exactly one cargo publish line, and it is cargo publish --workspace --locked --no-verify" "1 1" "$(printf '%s\n' "$PJ" | grep -cE 'cargo publish') $(printf '%s\n' "$PJ" | grep -cE '^[[:space:]]*(run: )?cargo publish --workspace --locked --no-verify[[:space:]]*$')"
expect_eq "publish.yml: no cargo build, test, check, run or install anywhere in the publish job (nothing compiles in the job that holds the tokens)" 0 "$(printf '%s\n' "$PJ" | grep -cE 'cargo (build|test|check|run|install|clippy|doc)')"
S_PKG=$(step_of "$PJ" 'cargo package --workspace'); S_DIG=$(step_of "$PJ" 'publish-guard\.sh crate-digests'); S_PUB=$(step_of "$PJ" '^[[:space:]]*(run: )?cargo publish --workspace'); S_IDX=$(step_of "$PJ" 'publish-guard\.sh crate-index'); S_PY=$(step_of "$PJ" 'gh-action-pypi-publish@'); S_ST=$(step_of "$PJ" 'Stage exactly the PyPI files'); S_NPM=$(step_of "$PJ" '^[[:space:]]*(run: )?npm publish ')
expect_eq "publish.yml: the re-package and the digest compare are one step" "$S_PKG" "$S_DIG"
expect_eq "publish.yml: cargo publish is the very next step after the digest compare (nothing between them)" "$((S_DIG + 1))" "$S_PUB"
expect_eq "publish.yml: the re-package step holds no secret and no token variable" 0 "$(step_text "$PJ" "$S_PKG" | grep -cE 'secrets\.|TOKEN')"
expect_eq "publish.yml: the cargo publish step is the one with CARGO_REGISTRY_TOKEN" 1 "$(step_text "$PJ" "$S_PUB" | grep -cF 'CARGO_REGISTRY_TOKEN: ${{ secrets.CARGO_REGISTRY_TOKEN }}')"
expect_eq "publish.yml: the crates.io index check is the step right after cargo publish" "$((S_PUB + 1))" "$S_IDX"
expect_eq "publish.yml: the index check passes GUARD_VERSION from the shell variable, with the default window (no extra arguments)" 1 "$(code_lines "$PUB" | grep -cE '^[[:space:]]*run: GUARD_VERSION="\$VERSION" scripts/release/publish-guard\.sh crate-index verified[[:space:]]*$')"
expect_eq "publish.yml: the whole crates sequence (package, digests, publish, index check) comes before the PyPI staging step and the PyPI action" 1 "$( [ "$S_PKG" -gt 0 ] && [ "$S_IDX" -gt 0 ] && [ "$S_IDX" -lt "$S_ST" ] && [ "$S_ST" -lt "$S_PY" ] && echo 1 || echo 0)"
expect_eq "publish.yml: the crates sequence comes after npm publish (provenance first, then npm, then the crates)" 1 "$( [ "$S_NPM" -gt 0 ] && [ "$S_NPM" -lt "$S_PKG" ] && echo 1 || echo 0)"
expect_eq "publish-dry-run.sh: the crates dry run is cargo publish --dry-run --workspace --locked --no-verify" 1 "$(code_lines "$DRY" | grep -vE '^[[:space:]]*(echo|printf|note|die) ' | grep -cF 'cargo publish --dry-run --workspace --locked --no-verify')"
expect_eq "publish-dry-run.sh: the command is publish.yml's command with --dry-run inserted" "$(code_lines "$PUB" | grep -E '^[[:space:]]*(run: )?cargo publish ' | sed -E 's/^[[:space:]]*(run: )?//')" "$(code_lines "$DRY" | grep -vE '^[[:space:]]*(echo|printf|note|die) ' | grep -oE 'cargo publish --dry-run --workspace --locked --no-verify' | sed 's/ --dry-run//')"
if [ -f "$BA" ]; then
  BCM=$(code_lines "$BA")
  expect_eq "build-artefacts.sh: the crates are packaged with and without --no-verify (the signed bytes come from the verified run, the publish job re-packages with --no-verify)" 1 "$(printf '%s\n' "$BCM" | grep -cE 'for mode in verify noverify; do')"
  expect_eq "build-artefacts.sh: a --no-verify run that differs from the verified bytes fails the build (S1-131)" 1 "$(printf '%s\n' "$BCM" | grep -cE '\[ "\$A" = "\$C" \] && \[ "\$A" = "\$D" \] \|\| die .*S1-131' | awk '{print ($1 >= 1) ? 1 : 0}')"
  expect_eq "build-artefacts.sh: it says so when the --no-verify bytes equal the verified bytes" 1 "$(printf '%s\n' "$BCM" | grep -cF 'ok: cargo package --workspace --locked --no-verify gives the same .crate bytes as the verified run, two runs each (S1-131)')"
  expect_eq "build-artefacts.sh: one cargo package line, carrying the mode flag" 1 "$(printf '%s\n' "$BCM" | grep -cE '^[[:space:]]*\( unset RUSTFLAGS; cargo package --workspace --locked .*MODE_FLAG\[@\]')"
fi
if [ -f "$GUARD" ]; then
  GCM=$(code_lines "$GUARD")
  expect_eq "publish-guard.sh: crate-index reads only https://index.crates.io" 1 "$(printf '%s\n' "$GCM" | grep -cF 'url="https://index.crates.io/')"
  expect_eq "publish-guard.sh: crate-index retries for at most 600 seconds (default window 600, interval 15)" 1 "$(printf '%s\n' "$GCM" | grep -cE 'window=600 interval=15')"
  expect_eq "publish-guard.sh: crate-index compares the cksum with the verified manifest's sha256 and refuses a different one at once" 1 "$(printf '%s\n' "$GCM" | grep -cE 'h\.cksum !== want')"
fi

# N. FR2 BUG-T3-S7-20: no continue-on-error anywhere in publish.yml; no step-level if: in the publish job; the build job's one step-level if is listed exactly
if [ -f "$PUB" ]; then
  echo "== N. FR2: continue-on-error and step-level if in publish.yml"
  expect_eq "publish.yml: no continue-on-error anywhere (a failed check must stop the publish)" 0 "$(code_lines "$PUB" | grep -c 'continue-on-error')"
  expect_eq "publish.yml publish job: no step-level if: (every step runs, in order, or the job stops)" 0 "$(job_text "$PUB" publish | grep -vE '^[[:space:]]*#' | grep -cE '^        if:')"
  expect_eq "publish.yml build job: the only step-level if: is the ubuntu-only wasm tool install" "if: matrix.os == 'ubuntu-latest'" "$(job_text "$PUB" build | grep -vE '^[[:space:]]*#' | grep -E '^        if:' | sed -E 's/^[[:space:]]+//' | tr '\n' '|' | sed 's/|$//')"
fi

finish
