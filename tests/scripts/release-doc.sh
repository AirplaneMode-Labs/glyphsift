#!/usr/bin/env bash
# D3-03: the release document and the version are consistent.
#
#   tests/scripts/release-doc.sh
#
#  A. BUG-T3-S4-24: row 6 of docs/release.md cites exactly one `gates-*.log` (the artifact-size log). In
#     Sprint 4 it cited the superseded gates-fix1 log next to the current gates-fix2 one.
#  B. The first CI run of the `wheels` job (run 43667702791 at 5ff0c47, read with gh on 18 Nov 2026) is recorded:
#     run id, commit, job names, artifact names, file names and sizes, what it proved and what it did not.
#     The document no longer says the wheels job was never run.
#  C. One version everywhere: the workspace version is the version of every crate, of the Cargo.lock entries
#     of the four glyphsift crates, of the glyphsift-core dependency declaration, of the wheel (maturin takes
#     it from Cargo) and of the npm package.json (scripts/package-npm.sh writes it from Cargo.toml); the
#     CHANGELOG has an entry for it; the README names it.
#  D. Fix round 1 (BUG-T2-S5-07, TD-56): docs/release.md says that local macOS wheels are not byte-reproducible across
#     checkout paths and that only CI-built wheels are signed and published, and that the sdist is a source release that
#     deliberately includes crates/*/tests.
#  E. Fix round 1 (BUG-T2-S5-02, TD-53): docs/release.md has the section "Output confinement of release-manifest.mjs" (the
#     rules, what is not closed) and the owner's push-list line for the Windows leg that proves it.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1
REL=docs/release.md
[ -f "$REL" ] || { echo "error: $REL not found" >&2; exit 1; }

echo "== A. row 6 cites exactly one gates log"
ROW6=$(grep -E '^\| 6 \|' "$REL")
expect_eq "docs/release.md has exactly one row 6" 1 "$(printf '%s\n' "$ROW6" | grep -c .)"
GATES=$(printf '%s\n' "$ROW6" | grep -oE 'gates-[A-Za-z0-9._-]*\.log' | sort -u)
expect_eq "row 6 names exactly one gates-*.log" 1 "$(printf '%s\n' "$GATES" | grep -c .)"
case "$GATES" in *fix1*) fail "row 6 does not cite the superseded gates-fix1 log" ;; *) ok "row 6 does not cite the superseded gates-fix1 log" ;; esac
LOGPATHS=$(printf '%s\n' "$ROW6" | grep -oE 'evidence/sprint-[0-9]+/D3/gates-[A-Za-z0-9._-]*\.log' | sort -u | grep -c .)
expect_eq "that log is cited with its evidence path" 1 "$LOGPATHS"

echo "== B. the first CI run of the wheels job is recorded"
SECTION=$(awk '/^## First CI run of the wheels job/{on=1; print; next} on && /^## /{exit} on{print}' "$REL")
if [ -n "$SECTION" ]; then ok "docs/release.md has the section 'First CI run of the wheels job'"; else fail "docs/release.md has the section 'First CI run of the wheels job'"; fi
need() { if printf '%s\n' "$SECTION" | grep -qF -- "$1"; then ok "the section cites $2"; else fail "the section cites $2 ($1)"; fi; }
need "43667702791" "the run id"
need "5ff0c47" "the commit"
need "18 Nov 2026" "the date it was read"
need "wheel and sdist (ubuntu-latest)" "the ubuntu job name"
need "wheel and sdist (windows-latest)" "the windows job name"
need "wheel and sdist (macos-latest)" "the macos job name"
need "glyphsift-wheels-ubuntu-latest" "the ubuntu artifact name"
need "glyphsift-wheels-windows-latest" "the windows artifact name"
need "glyphsift-wheels-macos-latest" "the macos artifact name"
need "glyphsift-0.1.0-cp39-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64.whl" "the manylinux wheel file name"
need "254,335" "the manylinux wheel size"
need "glyphsift-0.1.0-cp39-abi3-win_amd64.whl" "the win_amd64 wheel file name"
need "151,328" "the win_amd64 wheel size"
need "glyphsift-0.1.0-cp39-abi3-macosx_11_0_arm64.whl" "the macOS wheel file name"
need "247,045" "the macOS wheel size"
need "glyphsift-0.1.0.tar.gz" "the sdist file name"
need "82,081" "the sdist size"
need "ppm 1000000" "the smoke call every wheel passed"
need "Nothing is published" "that nothing is published"
need "S1-103" "that the sdist was built but never built --locked (S1-103)"
if grep -qF 'configured in the `wheels` job, never run' "$REL"; then fail "release.md no longer calls the wheels job 'never run'"; else ok "release.md no longer calls the wheels job 'never run'"; fi
if grep -qF 'Configured, not yet run: only CI after the owner' "$REL"; then fail "release.md no longer calls the wheels job 'not yet run'"; else ok "release.md no longer calls the wheels job 'not yet run'"; fi

echo "== C. one version everywhere"
VERSION=$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
[ -n "$VERSION" ] || { fail "the workspace version is readable"; finish; exit $?; }
ok "the workspace version is $VERSION"
# Sprint 5 (TD-43) sets glyphsift to 0.1.1; the next version bump edits this line, on purpose.
expect_eq "the workspace version is the Sprint 5 version" "0.1.1" "$VERSION"
for c in crates/*/Cargo.toml; do
  if grep -qx 'version.workspace = true' "$c"; then ok "$c takes the workspace version"; else fail "$c takes the workspace version"; fi
done
DEP=$(sed -n 's/^glyphsift-core = { path = "crates\/glyphsift-core", version = "\(.*\)" }$/\1/p' Cargo.toml)
expect_eq "the glyphsift-core dependency declares the workspace version" "$VERSION" "$DEP"
for k in glyphsift-core glyphsift-cli glyphsift-py glyphsift-wasm; do
  LV=$(awk -v n="$k" '$0=="name = \"" n "\""{getline; sub(/^version = "/,""); sub(/"$/,""); print; exit}' Cargo.lock)
  expect_eq "Cargo.lock has $k at the workspace version" "$VERSION" "$LV"
done
if grep -qE '^version[[:space:]]*=' crates/glyphsift-py/pyproject.toml; then fail "the wheel version is dynamic (maturin takes it from Cargo)"; else ok "the wheel version is dynamic (maturin takes it from Cargo)"; fi
if grep -qF 'dynamic = ["version"]' crates/glyphsift-py/pyproject.toml; then ok "pyproject declares dynamic = [\"version\"]"; else fail "pyproject declares dynamic = [\"version\"]"; fi
if grep -qF 'workspace.package' scripts/package-npm.sh && grep -qF '"version": "$VERSION"' scripts/package-npm.sh; then
  ok "package-npm.sh writes package.json's version from the workspace version"
else
  fail "package-npm.sh writes package.json's version from the workspace version"
fi
if grep -qE "^## \\[${VERSION//./\\.}\\]" CHANGELOG.md || awk '/^## \[Unreleased\]/{on=1; next} on && /^## \[/{exit} on{print}' CHANGELOG.md | grep -qF "$VERSION"; then
  ok "CHANGELOG.md has an entry for $VERSION"
else
  fail "CHANGELOG.md has an entry for $VERSION"
fi
if sed -n '/^## Status/,/^## Install/p' README.md | grep -qF "$VERSION"; then ok "the README Status names $VERSION"; else fail "the README Status names $VERSION"; fi
# A built artifact name in a README must carry the current version (the 0.1.0 names are the CI run's, quoted in docs/release.md only).
for f in README.md npm/README.md crates/glyphsift-py/README.md; do
  if grep -qE "glyphsift-0\.1\.0|airplanemode-glyphsift-0\.1\.0" "$f" && [ "$VERSION" != "0.1.0" ]; then fail "$f names no artifact of an older version"; else ok "$f names no artifact of an older version"; fi
done

echo "== D. packaging notes: local wheels are not reproducible, the sdist includes tests"
PN=$(awk '/^## Packaging notes/{on=1; print; next} on && /^## /{exit} on{print}' "$REL")
if [ -n "$PN" ]; then ok "docs/release.md has the section 'Packaging notes'"; else fail "docs/release.md has the section 'Packaging notes'"; fi
pn() { if printf '%s\n' "$PN" | tr '\n' ' ' | sed 's/  */ /g' | grep -qF -- "$1"; then ok "the packaging notes say $2"; else fail "the packaging notes say $2 ($1)"; fi; }
pn "Local macOS wheels are not byte-reproducible across checkout paths" "that local macOS wheels are not byte-reproducible across checkout paths"
pn 'Mach-O `LC_UUID`' "why: the Mach-O LC_UUID"
pn "ad-hoc code signature" "why: the ad-hoc code signature"
pn "Only CI-built wheels are signed and published" "that only CI-built wheels are signed and published"
pn "BUG-T2-S5-07" "which bug it closes (BUG-T2-S5-07)"
pn "The sdist is a source release and deliberately includes" "that the sdist is a source release that deliberately includes tests"
pn '`crates/*/tests`' "which files (crates/*/tests)"
pn "TD-56" "which decision records it (TD-56)"
expect_eq "no 'byte-reproducible' claim for local wheels outside the packaging notes (README, RELEASING.md)" 0 "$(grep -hiE 'wheels? .*(are|is) (byte-)?reproducible|reproducible wheels?' README.md docs/RELEASING.md | grep -vciE 'not (byte-)?reproducible')"

# Fix round 2 (BUG-T2-S5-12): the sentence about `cargo test --locked` from the sdist is true, and tests/scripts/sdist-locked.sh checks it.
pn "ships three repository-root files" "that the sdist ships the three repository-root files the gate tests read"
pn '`bench/corpus/clean.txt`, `docs/gate.md` and `docs/score-vs-noise.csv`' "which three files"
pn "synthetic and own-authored" "that the three files are synthetic and own-authored"
pn "scripts/add-sdist-files.py" "which script adds them"
pn '`cargo test --locked --no-fail-fast -p glyphsift-core`' "the exact command tests/scripts/sdist-locked.sh runs from the unpacked sdist"
expect_eq "row 6 no longer cites the pre-fix-round-2 sdist size 95,605" 0 "$(printf '%s\n' "$ROW6" | grep -c '95,605')"
expect_eq "row 6 mentions the sdist's cargo test" 1 "$(printf '%s\n' "$ROW6" | grep -c 'cargo test --locked')"

# Fix round 2 (T3-R1-03): row 2 quotes the 8 GB cell as the README does.
ROW2=$(grep -E '^\| 2 \|' "$REL")
expect_eq "row 2 quotes \"not measured on 8 GB\" for the 8 GB column" 1 "$(printf '%s\n' "$ROW2" | grep -cF 'reads "not measured on 8 GB"')"
expect_eq "row 2 no longer says the column reads just \"not measured\"" 0 "$(printf '%s\n' "$ROW2" | grep -cF 'reads "not measured".')"

echo "== E. output confinement is documented"
OC=$(awk '/^## Output confinement of/{on=1; print; next} on && /^## /{exit} on{print}' "$REL")
if [ -n "$OC" ]; then ok "docs/release.md has the section 'Output confinement of release-manifest.mjs'"; else fail "docs/release.md has the section 'Output confinement of release-manifest.mjs'"; fi
oc() { if printf '%s\n' "$OC" | tr '\n' ' ' | sed 's/  */ /g' | grep -qF -- "$1"; then ok "the confinement section says $2"; else fail "the confinement section says $2 ($1)"; fi; }
oc "scripts/lib/confine.mjs" "where the check lives"
oc "tests/scripts/confine.test.mjs" "which unit tests prove the Windows rules"
oc "tests/scripts/release-manifest.sh" "which script test uses real links"
oc "TD-53" "which decision brought it to glyphsift"
oc "hard link" "what a hard link does (the name is replaced, the other name keeps its bytes)"
oc "junction" "the junction rule"
oc "What is not closed" "what is not closed"
oc "glyphsift check (windows-latest) proves the ported containment" "the owner's push-list line"
expect_eq "scripts/lib/confine.mjs names its source (pagetriage) in its header" 1 "$(head -5 scripts/lib/confine.mjs 2>/dev/null | grep -c 'pagetriage')"
expect_eq "scripts/release-manifest.mjs imports confineOutput and writeConfined" 1 "$(grep -cE '^import \{[^}]*confineOutput[^}]*writeConfined[^}]*\} from "\./lib/confine\.mjs";' scripts/release-manifest.mjs)"
expect_eq "scripts/release-manifest.mjs no longer writes with writeFileSync" 0 "$(grep -c 'writeFileSync' scripts/release-manifest.mjs)"

finish
