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
#  K. Sprint 7 fix round 1 (BUG-T3-S7-01 / S1-130, BUG-S1-S7-03 / S1-131, BUG-T3-S7-07, TD-125, S1-135): docs/release.md records each fix and the push-list lines that
#     only CI can prove, docs/RELEASING.md tells the owner to compare the npm tarball, the sdist and the crates with an independent build before signing (wheels only
#     across the two CI builds), to arm just before approving, and what the publish job does for the crates (no build, digests, index check), and the CHANGELOG cites the ids.
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
need() { if printf '%s\n' "$SECTION" | gq -F -- "$1"; then ok "the section cites $2"; else fail "the section cites $2 ($1)"; fi; }
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
# Sprint 7 (TD-107) sets glyphsift to 0.1.3; the next version bump edits this line, on purpose.
expect_eq "the workspace version is the Sprint 7 version" "0.1.3" "$VERSION"
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
if grep -qE "^## \\[${VERSION//./\\.}\\]" CHANGELOG.md || awk '/^## \[Unreleased\]/{on=1; next} on && /^## \[/{exit} on{print}' CHANGELOG.md | gq -F "$VERSION"; then
  ok "CHANGELOG.md has an entry for $VERSION"
else
  fail "CHANGELOG.md has an entry for $VERSION"
fi
if sed -n '/^## Status/,/^## Install/p' README.md | gq -F "$VERSION"; then ok "the README Status names $VERSION"; else fail "the README Status names $VERSION"; fi
# A built artifact name in a README must carry the current version (the 0.1.0 names are the CI run's, quoted in docs/release.md only).
for f in README.md npm/README.md crates/glyphsift-py/README.md; do
  if grep -qE "glyphsift-0\.1\.[0-2]([^0-9]|$)|airplanemode-glyphsift-0\.1\.[0-2]([^0-9]|$)" "$f" && [ "$VERSION" != "0.1.2" ]; then fail "$f names no artifact of an older version"; else ok "$f names no artifact of an older version"; fi
done

echo "== D. packaging notes: local wheels are not reproducible, the sdist includes tests"
PN=$(awk '/^## Packaging notes/{on=1; print; next} on && /^## /{exit} on{print}' "$REL")
if [ -n "$PN" ]; then ok "docs/release.md has the section 'Packaging notes'"; else fail "docs/release.md has the section 'Packaging notes'"; fi
pn() { if printf '%s\n' "$PN" | tr '\n' ' ' | sed 's/  */ /g' | gq -F -- "$1"; then ok "the packaging notes say $2"; else fail "the packaging notes say $2 ($1)"; fi; }
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
pn "ships four repository-root files" "that the sdist ships the four repository-root files its tests read (S1-118)"
pn '`bench/corpus/clean.txt`, `docs/gate.md`, `docs/score-vs-noise.csv` and `docs/corruption-generator.md`' "which four files"
pn "synthetic and own-authored" "that the four files are synthetic and own-authored"
pn "scripts/add-sdist-files.py" "which script adds them"
pn '`cargo test --locked --no-fail-fast -p glyphsift-core --features corrupt`' "the exact command tests/scripts/sdist-locked.sh runs from the unpacked sdist (S1-118)"
pn "S1-118" "which finding it closes (S1-118)"
pn "BUG-T2-S5-15" "BUG-T2-S5-15 (the shipped corrupt tests never ran)"
pn 'is not in the sdist: maturin ships only `glyphsift-core` and `glyphsift-py`' "why the CLI corrupt test is absent from the sdist"
expect_eq "row 6 no longer cites the pre-fix-round-2 sdist size 95,605" 0 "$(printf '%s\n' "$ROW6" | grep -c '95,605')"
expect_eq "row 6 mentions the sdist's cargo test" 1 "$(printf '%s\n' "$ROW6" | grep -c 'cargo test --locked')"

# Fix round 2 (T3-R1-03): row 2 quotes the 8 GB cell as the README does.
ROW2=$(grep -E '^\| 2 \|' "$REL")
expect_eq "row 2 quotes \"not measured on 8 GB\" for the 8 GB column" 1 "$(printf '%s\n' "$ROW2" | grep -cF 'reads "not measured on 8 GB"')"
expect_eq "row 2 no longer says the column reads just \"not measured\"" 0 "$(printf '%s\n' "$ROW2" | grep -cF 'reads "not measured".')"

echo "== F. Sprint 6: CARGO_TARGET_DIR, the sdist's corrupt tests and the log row 6 cites (S1-118, BUG-T2-S5-14/-15/-16); Sprint 7 moves row 6 to its own gates log"
expect_eq "row 6 cites evidence/sprint-7/D3/gates-s7.log" 1 "$(printf '%s\n' "$ROW6" | grep -c 'evidence/sprint-7/D3/gates-s7.log')"
expect_eq "row 6 names the sdist's corrupt-feature test run" 1 "$(printf '%s\n' "$ROW6" | grep -c -- '--features corrupt')"
S6=$(awk '/^## Sprint 6 carry-overs closed here/{on=1; print; next} on && /^## /{exit} on{print}' "$REL")
if [ -n "$S6" ]; then ok "docs/release.md has the section 'Sprint 6 carry-overs closed here'"; else fail "docs/release.md has the section 'Sprint 6 carry-overs closed here'"; fi
s6() { if printf '%s\n' "$S6" | tr '\n' ' ' | sed 's/  */ /g' | gq -F -- "$1"; then ok "the Sprint 6 section says $2"; else fail "the Sprint 6 section says $2 ($1)"; fi; }
s6 "S1-118" "S1-118"
s6 "BUG-T2-S5-14" "BUG-T2-S5-14 (build-wasm.sh and the native leg honour CARGO_TARGET_DIR)"
s6 "BUG-T2-S5-15" "BUG-T2-S5-15"
s6 "BUG-T2-S5-16" "BUG-T2-S5-16"
s6 "tests/scripts/cargo-target-dir.sh" "which test proves CARGO_TARGET_DIR"
s6 "docs/what-glyphsift-measures.md" "where the measures page is"
s6 "glyphsift | packaging dry runs (wheel, npm tarball, release manifest) | proves S1-118" "the owner's push-list line for S1-118 (the job that runs the sdist test)"
s6 "glyphsift | determinism (windows-latest) | proves BUG-T2-S5-14" "the owner's push-list line for the Windows native leg"
echo "== E. output confinement is documented"
OC=$(awk '/^## Output confinement of/{on=1; print; next} on && /^## /{exit} on{print}' "$REL")
if [ -n "$OC" ]; then ok "docs/release.md has the section 'Output confinement of release-manifest.mjs'"; else fail "docs/release.md has the section 'Output confinement of release-manifest.mjs'"; fi
oc() { if printf '%s\n' "$OC" | tr '\n' ' ' | sed 's/  */ /g' | gq -F -- "$1"; then ok "the confinement section says $2"; else fail "the confinement section says $2 ($1)"; fi; }
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

echo "== F. BUG-T3-S6-R2-08: the wheel size is quoted in KiB, not as a path-dependent byte count"
expect_eq "docs/release.md does not quote the exact wheel byte count 254,197" 0 "$(grep -c '254,197' "$REL")"
if tr '\n' ' ' < "$REL" | sed 's/  */ /g' | gq -E 'about 24[0-9] KiB'; then ok "the wheel size is given in KiB"; else fail "the wheel size is given in KiB (about 24x KiB)"; fi
if tr '\n' ' ' < "$REL" | sed 's/  */ /g' | gq -F 'varies by a few bytes with the checkout path'; then ok "the document says the wheel bytes vary with the checkout path"; else fail "the document says the wheel bytes vary with the checkout path"; fi
expect_eq "the sdist size is quoted in KiB (about 115 KiB), not as a README-dependent byte count" 1 "$(tr '\n' ' ' < "$REL" | sed 's/  */ /g' | grep -c 'the sdist is about 115 KiB' | awk '{print ($1>=1)?1:0}')"

echo "== G. BUG-T3-S6-R2-01: the CHANGELOG [0.1.2] cites the confinement port and the target-dir fix"
CL=$(sed -n '/^## \[0.1.2\]/,/^## \[0.1.1\]/p' CHANGELOG.md)
for id in S1-106 COM0 BUG-T2-S6-06 cargo-target-dir.sh BUG-T3-S6-02 "real NTFS after the push"; do
  if printf '%s\n' "$CL" | gq -F -- "$id"; then ok "CHANGELOG [0.1.2] cites $id"; else fail "CHANGELOG [0.1.2] cites $id"; fi
done

echo "== H. Sprint 7 (D3-01): the CHANGELOG [0.1.3] is dated 20 Nov 2026, untagged, and cites the task, decision and finding ids"
grep -qE '^## \[0\.1\.3\] - 2026-11-20 \(untagged\)$' CHANGELOG.md && ok "CHANGELOG.md has the heading '## [0.1.3] - 2026-11-20 (untagged)'" || fail "CHANGELOG.md has the heading '## [0.1.3] - 2026-11-20 (untagged)'"
CL3=$(sed -n '/^## \[0.1.3\]/,/^## \[0.1.2\]/p' CHANGELOG.md)
for id in D3-01 D3-02 D3-03 D3-04 TD-103 TD-106 TD-107 TD-118 TD-123 S1-126; do
  if printf '%s\n' "$CL3" | gq -F -- "$id"; then ok "CHANGELOG [0.1.3] cites $id"; else fail "CHANGELOG [0.1.3] cites $id"; fi
done
for g in Added Changed Fixed Security Deferred; do
  if printf '%s\n' "$CL3" | gq -E "^### $g\$"; then ok "CHANGELOG [0.1.3] has the group '$g'"; else fail "CHANGELOG [0.1.3] has the group '$g'"; fi
done
if awk '/^## \[Unreleased\]/{on=1; next} on && /^## \[/{exit} on{print}' CHANGELOG.md | gq '[^[:space:]]'; then fail "[Unreleased] is empty once the entry is dated"; else ok "[Unreleased] is empty once the entry is dated"; fi

echo "== I. Sprint 7 (D3-02, D3-03, D3-06): what the rehearsal and the publish workflow prove, and what only the push can"
S7=$(awk '/^## Sprint 7 carry-overs closed here/{on=1; print; next} on && /^## /{exit} on{print}' "$REL")
if [ -n "$S7" ]; then ok "docs/release.md has the section 'Sprint 7 carry-overs closed here'"; else fail "docs/release.md has the section 'Sprint 7 carry-overs closed here'"; fi
s7() { if printf '%s\n' "$S7" | tr '\n' ' ' | sed 's/  */ /g' | gq -F -- "$1"; then ok "the Sprint 7 section says $2"; else fail "the Sprint 7 section says $2 ($1)"; fi; }
s7 "scripts/release/rehearse.sh" "which script is the rehearsal"
s7 "release-rehearsal (<os>)" "the new job name"
s7 "replaces the \`wheels\` job" "that the wheels job is folded in"
s7 "scripts/release/publish-guard.sh" "which script holds the publish checks"
s7 "tests/scripts/publish-guard.sh" "which test proves each refusal"
s7 "S1-126" "S1-126 (the two cargo package runs)"
s7 "TD-123" "TD-123"
s7 "TD-103" "TD-103"
s7 "TD-105" "TD-105 (the six locks)"
s7 "TD-122" "TD-122 (the token lifetime)"
s7 "not measured on 8 GB" "that no 8 GB figure exists"
s7 "evidence/sprint-7/D3/" "where the evidence is"
PL=$(awk '/^## Sprint 7: what only CI can prove/{on=1; print; next} on && /^## /{exit} on{print}' "$REL")
if [ -n "$PL" ]; then ok "docs/release.md has the section 'Sprint 7: what only CI can prove'"; else fail "docs/release.md has the section 'Sprint 7: what only CI can prove'"; fi
for os in ubuntu-latest macos-latest windows-latest; do
  expect_eq "the push list names the release-rehearsal ($os) job" 1 "$(printf '%s\n' "$PL" | grep -c "glyphsift | release-rehearsal ($os) |")"
done
for t in "release rehearsal ok on" "refused: test_key_refused" "refused: no_trusted_key" "release vectors through release-tool.mjs" "Installed package" "glyphsift-core v" "installed wheel check: all checks passed" "installed node check: all checks passed" "installed cli check: all checks passed" "ok: two cargo package --workspace --locked runs give identical .crate bytes"; do
  expect_eq "the push list quotes the log text '$t'" 1 "$(printf '%s\n' "$PL" | grep -cF -- "$t" | awk '{print ($1 >= 1) ? 1 : 0}')"
done
expect_eq "the push list says the junction case runs on Windows only" 1 "$(printf '%s\n' "$PL" | grep -ci 'junction' | awk '{print ($1 >= 1) ? 1 : 0}')"
expect_eq "the push list says publish.yml is never run by the team" 1 "$(printf '%s\n' "$PL" | grep -c 'publish.yml' | awk '{print ($1 >= 1) ? 1 : 0}')"
CURRENT=$( { grep -E '^\| [1-7] \|' "$REL"; awk '/^## Owner must/{on=1} on && /^## /&&!/^## Owner must/{exit} on{print}' "$REL"; printf '%s\n%s\n' "$S7" "$PL"; } )
expect_eq "the current rows, the Owner-must section and the Sprint 7 sections name no 'wheel and sdist (' job (the old wheels job is folded into release-rehearsal; the first-run tables are history)" 0 "$(printf '%s\n' "$CURRENT" | grep -c 'wheel and sdist (')"
ROW7=$(grep -E '^\| 7 \|' "$REL")
expect_eq "row 7 reads 'draft exists; finishing it waits on the 8 GB figure (owner)'" 1 "$(printf '%s\n' "$ROW7" | grep -cF 'draft exists; finishing it waits on the 8 GB figure (owner)')"
WU=docs/writeup-0.1.3-draft.md
if [ -f "$WU" ]; then
  ok "$WU exists"
  expect_eq "the write-up draft is marked 'draft, not published'" 1 "$(head -12 "$WU" | grep -c 'draft, not published' | awk '{print ($1 >= 1) ? 1 : 0}')"
  expect_eq "the write-up draft has the three headings: what was tried, what held up, what did not" 3 "$(grep -cE '^## (What was tried|What held up|What did not)' "$WU")"
  expect_eq "the write-up draft reads 'not measured on 8 GB' for the laptop figures" 1 "$(grep -c 'not measured on 8 GB' "$WU" | awk '{print ($1 >= 1) ? 1 : 0}')"
  expect_eq "the write-up draft makes no compliance, audit, cost-saving or 'published' claim" 0 "$(grep -iE 'compliant|compliance|audited|cost[- ]saving|is published|are published|has been published' "$WU" | grep -vciE 'not published|nothing is published|unpublished')"
  expect_eq "the write-up draft names no person, employer or prospect" 0 "$(grep -ciE 'sarvam|ai4bharat|employer|customer name|prospect' "$WU")"
  # every number in the draft cites a committed file on its own line or in the sentence before it
  expect_eq "the write-up draft cites the committed benchmark and the measures page" 2 "$(grep -cE 'docs/score-vs-noise\.csv|docs/what-glyphsift-measures\.md' "$WU" | awk '{print ($1 >= 2) ? 2 : $1}')"
else
  fail "$WU exists"
fi

echo "== J. Sprint 7 (D3-03): docs/RELEASING.md lists only the owner's steps, in order, each with its reason"
RLS=docs/RELEASING.md
need2() { if tr '\n' ' ' < "$RLS" | sed 's/  */ /g' | gq -F -- "$1"; then ok "RELEASING.md has $2"; else fail "RELEASING.md has $2 ($1)"; fi; }
need2 "## Owner-only steps, in order" "the owner-only steps heading"
NSTEPS=$(grep -cE '^### [0-9]+\. ' "$RLS")
if [ "$NSTEPS" -ge 12 ]; then ok "RELEASING.md has $NSTEPS numbered steps"; else fail "RELEASING.md has at least 12 numbered steps (found $NSTEPS)"; fi
expect_eq "every step has a 'Why only you:' line" "$NSTEPS" "$(grep -c '^Why only you: ' "$RLS")"
expect_eq "the steps are numbered 1 to $NSTEPS in order" "$(seq 1 "$NSTEPS" | tr '\n' ' ')" "$(grep -E '^### [0-9]+\. ' "$RLS" | sed -E 's/^### ([0-9]+)\..*/\1/' | tr '\n' ' ')"
need2 "gh api -X PUT repos/AirplaneMode-Labs/glyphsift/environments/release" "the command that creates the release environment"
need2 "can_admins_bypass" "administrators cannot bypass the environment"
need2 "custom_branch_policies" "a custom branch policy on the environment"
need2 "deployment-branch-policies" "the call that limits the environment to main"
need2 "gh variable set RELEASE_KEY_ID --env release" "RELEASE_KEY_ID as a variable of the environment"
need2 "gh variable set RELEASE_PUBLISH_ARMED --env release" "arming with RELEASE_PUBLISH_ARMED"
need2 "gh variable delete RELEASE_PUBLISH_ARMED --env release" "disarming again"
need2 "gh secret set NPM_TOKEN --env release" "NPM_TOKEN as a secret of the environment only"
need2 "gh secret set CARGO_REGISTRY_TOKEN --env release" "CARGO_REGISTRY_TOKEN as a secret of the environment only"
need2 "gh secret delete NPM_TOKEN --env release" "deleting the npm secret after the release"
need2 "7 days" "the token lifetime (7 days or less, TD-122)"
need2 "revoke" "the revoke step"
need2 "Project name" "the PyPI pending-publisher field 'Project name'"
need2 "Workflow name" "the PyPI pending-publisher field 'Workflow name'"
need2 "Environment name" "the PyPI pending-publisher field 'Environment name'"
need2 "publish.yml" "the workflow file name"
need2 "gh run view" "the candidate-provenance check (gh run view)"
need2 "headSha" "that the run's head commit is compared with the tag commit"
need2 "cp-sign -- sign --key ./keys/key.secret" "the offline cp-sign signature (from the control-plane checkout, with the real key)"
need2 "--no-expiry" "the no-expiry flag (TD-121)"
need2 "release-tool.mjs verify" "verification with the vendored release tool"
need2 "--trust-file docs/release-keys.json" "verification against docs/release-keys.json"
need2 "gh release create v0.1.3" "the GitHub release that carries the signed manifest"
need2 "gh workflow run publish.yml" "the dispatch command"
need2 "git tag -s v0.1.3" "the signed tag"
need2 "published from source at the tagged commit" "the fallback if the packaged crates are not byte-identical (S1-126)"
need2 "tag ruleset" "the recommended tag ruleset"
need2 "CODEOWNERS" "the recommended CODEOWNERS entry for docs/release-keys.json"
expect_eq "RELEASING.md never tells anyone to run --allow-test-key or --trust-test-key for a release" 0 "$(grep -E -- '--allow-test-key|--trust-test-key' "$RLS" | grep -vciE 'never|not|only|rehearsal')"
expect_eq "RELEASING.md has no manual publish command (the workflow publishes)" 0 "$(grep -cE 'cargo publish|npm publish|twine upload|maturin publish' "$RLS")"
expect_eq "RELEASING.md names no older version (0.1.0, 0.1.1, 0.1.2 appear only as superseded)" 0 "$(grep -E '0\.1\.[012]([^0-9]|$)' "$RLS" | grep -vc 'superseded\|never tagged\|older')"
expect_eq "RELEASING.md gives every step a gh or shell command or a named page, not just prose" 1 "$(grep -cE '^```sh' "$RLS" | awk '{print ($1 >= 10) ? 1 : 0}')"


echo "== K. Sprint 7 fix round 1 (D3): the documents say what FR1 changed"
FR1=$(awk '/^## Sprint 7 fix round 1 \(D3\)/{on=1; print; next} on && /^## /{exit} on{print}' "$REL")
if [ -n "$FR1" ]; then ok "docs/release.md has the section 'Sprint 7 fix round 1 (D3)'"; else fail "docs/release.md has the section 'Sprint 7 fix round 1 (D3)'"; fi
fr1() { if printf '%s\n' "$FR1" | tr '\n' ' ' | sed 's/  */ /g' | gq -F -- "$1"; then ok "the fix-round section says $2"; else fail "the fix-round section says $2 ($1)"; fi; }
fr1 "S1-130" "S1-130 (the npm path)"
fr1 "./verified/" "that the npm argument starts with ./"
fr1 "npm-package-arg" "that npm's own resolver was asked"
fr1 "S1-131" "S1-131 (no build where the tokens are)"
fr1 "--no-verify" "that the crates are packaged and published with --no-verify"
fr1 "crates.io's sparse index" "the post-publish index check"
fr1 "10 minutes" "its retry window"
fr1 "before the PyPI action" "that the crates come before the third-party PyPI action"
fr1 "BUG-T3-S7-07" "BUG-T3-S7-07 (policy gaps and timeouts)"
fr1 "timeout-minutes" "the publish timeouts"
fr1 "ci-policy-mutations" "the mutation suite"
fr1 "TD-125" "TD-125 (the armed check is the first step after the checkout)"
fr1 "S1-135" "S1-135 (the independent build before signing)"
fr1 "FR1-REVENDOR" "the re-vendor of the release tool"
fr1 "not measured on 8 GB" "that no 8 GB figure exists"
expect_eq "the push list names the crates.io index check and the --no-verify bytes log text" 2 "$(printf '%s\n' "$PL" | grep -cF -e 'ok: cargo package --workspace --locked --no-verify gives the same .crate bytes as the verified run, two runs each (S1-131)' -e 'cargo-deny (advisories)' | awk '{print ($1 >= 2) ? 2 : $1}')"
expect_eq "the push list says what the first real publish run must show for the crates" 1 "$(printf '%s\n' "$PL" | grep -cF 'ok: both crates are in the crates.io index at' | awk '{print ($1 >= 1) ? 1 : 0}')"
expect_eq "the S1-126 row says the publish job packages with --no-verify" 1 "$(grep -E '^\| S1-126 and TD-123' "$REL" | grep -cF -- '--no-verify')"

need2 "independent build of the same commit" "the independent build before signing (S1-135)"
need2 "REHEARSAL-test-key-NOT-A-RELEASE-glyphsift-" "the push-CI artefact named as the comparison"
need2 "scripts/release/rehearse.sh" "the local rehearsal as the other comparison"
need2 "the npm tarball, the sdist and the two crates" "which files are compared byte for byte"
need2 "wheels compare only between the two CI builds" "that wheels compare only across the two CI builds"
need2 "just before you approve" "arming just before the approval"
need2 "--no-verify" "that the crates are published without a build"
need2 "crates.io's sparse index" "the index check after the crates publish"
need2 "npm first, then the crates, then PyPI" "the order of the three registries"
need2 "only in a step of the publish job" "that RELEASE_KEY_ID is read only in a publish-job step"
CL3=$(sed -n '/^## \[0.1.3\]/,/^## \[0.1.2\]/p' CHANGELOG.md)
for id in BUG-T3-S7-01 S1-130 BUG-S1-S7-03 S1-131 BUG-T3-S7-07 TD-125 S1-135 FR1-REVENDOR; do
  if printf '%s\n' "$CL3" | gq -F -- "$id"; then ok "CHANGELOG [0.1.3] cites $id"; else fail "CHANGELOG [0.1.3] cites $id"; fi
done

echo "== L. Sprint 7 fix round 2 (D3): recovery steps, and the key.pub to base64 command"
REC=$(awk '/^## If a publish step fails/{on=1; print; next} on && /^## /{exit} on{print}' "$RLS")
if [ -n "$REC" ]; then ok "RELEASING.md has the section 'If a publish step fails'"; else fail "RELEASING.md has the section 'If a publish step fails'"; fi
rec() { if printf '%s\n' "$REC" | tr '\n' ' ' | sed 's/  */ /g' | gq -F -- "$1"; then ok "the recovery section says $2"; else fail "the recovery section says $2 ($1)"; fi; }
rec "cargo yank" "to yank each crate"
rec "glyphsift-core" "which crates"
rec "glyphsift-cli" "which crates (cli)"
rec "npm deprecate" "to deprecate on npm"
rec "within 72 hours" "that npm unpublish is limited to 72 hours"
rec "gh variable delete RELEASE_PUBLISH_ARMED --env release" "to disarm RELEASE_PUBLISH_ARMED in the release environment"
rec "revoke both tokens" "to revoke both tokens"
rec "never re-publish" "never to re-publish the version"
rec "run id" "to record the run id"
rec "npm is published before the crate comparison" "that npm is published before the crate comparison in the current step order"
rec "leaves the npm package published" "that a refused crate comparison leaves npm published"
rec "the npm step of this section applies" "that the npm step then applies"

KP=$(awk '/^```sh keypub-b64$/{on=1; next} on && /^```$/{exit} on{print}' "$RLS")
if [ -n "$KP" ]; then
  ok "RELEASING.md has a keypub-b64 command block"
  KPD=$(mktemp -d); mkdir -p "$KPD/keys"
  # synthetic cp-sign-format key.pub holding the TEST 1 public key (see control-plane docs/key-custody.md for the file format)
  TEST1_PUB_HEX=$(node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(Buffer.from(j.keys[0].publicKey,"base64").toString("hex"))' scripts/release/vectors/keys/test-key.json)
  printf 'ed25519-public %s\n' "$TEST1_PUB_HEX" > "$KPD/keys/key.pub"
  GOT=$( cd "$KPD" && bash -c "$KP" 2>/dev/null | tr -d '\n')
  WANT=$(sed -n 's/.*"publicKey": *"\([^"]*\)".*/\1/p' scripts/release/vectors/keys/test-key.json 2>/dev/null | head -1)
  expect_eq "the documented key.pub to base64 command gives the vector publicKey" "$WANT" "$GOT"
  rm -rf "$KPD"
else
  fail "RELEASING.md has a keypub-b64 command block (waiting for D1/PUBKEY-B64-CMD.txt)"
fi

finish
