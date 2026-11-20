#!/usr/bin/env bash
# The dry run of every publish step, over the artefacts of a release directory (Sprint 7, D3-03; TD-105). CI's release rehearsal runs it on three
# operating systems (scripts/release/rehearse.sh calls it); publish.yml runs the same commands for real, behind its locks, with the same dist-tag
# derivation (scripts/release/publish-guard.sh dist-tag). NOTHING is published: every publish command below carries --dry-run, there is no login, no
# token, no .npmrc and no .pypirc, and a registry is only ever asked what it would do.
#
#   scripts/release/publish-dry-run.sh <release dir>
#
# <release dir> holds the artefacts a rehearsal built (the npm tarball, this platform's wheel, the two crates, on Linux the sdist). Steps:
#   1. npm publish "./verified/$(cat lists/npm.txt)" --dry-run --access public --ignore-scripts --tag <dist-tag>, run from a scratch directory laid out like
#      the publish job's working directory (verified/ holds the tarball, lists/npm.txt names it), so the argument is the workflow's own string, character for
#      character (S1-130: it starts with ./ because npm reads a bare `verified/<name>.tgz` as the GitHub shorthand user/repo); --provenance is added by the real
#      run only: it needs the workflow's OIDC token;
#   2. cargo publish --dry-run --workspace --locked --no-verify (the workflow's command with --dry-run, S1-131: no build): packages glyphsift-core then
#      glyphsift-cli as one unit and stops before the upload (glyphsift-py and glyphsift-wasm are publish = false and are skipped); the output must say that
#      the upload was aborted for the dry run;
#   3. the wheel metadata check (tests/python/check_wheel.py) on every wheel in the directory, which is what PyPI's page would show.
# REHEARSE_ALLOW_DIRTY=1 passes --allow-dirty to cargo (a local run from an uncommitted tree); CI never sets it. PYTHON names the interpreter.
set -euo pipefail
cd "$(dirname "$0")/../.."
DIE_PREFIX=publish-dry-run
# shellcheck source=scripts/release/lib-tools.sh
. scripts/release/lib-tools.sh

DIR=${1:-}
[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "usage: scripts/release/publish-dry-run.sh <release dir>" >&2; exit 2; }
DIR=$(cd "$DIR" && pwd -P)
PY=${PYTHON:-python3}
VERSION=$(scripts/release/publish-guard.sh version)
TAG=$(scripts/release/publish-guard.sh dist-tag "$VERSION")
echo "== dry run for glyphsift $VERSION, npm dist-tag '$TAG' (nothing is published)"

TGZ=$DIR/airplanemode-glyphsift-$VERSION.tgz
[ -f "$TGZ" ] || die "$TGZ is not in the release directory"
# the publish job's layout, in a scratch directory: ./verified/<name>.tgz and lists/npm.txt (the name), so the npm line below is the workflow's line
LAYOUT=$(mktemp -d "${TMPDIR:-/tmp}/publish-dry-run.XXXXXX")
trap 'case "$LAYOUT" in */publish-dry-run.??????) rm -rf "$LAYOUT" ;; esac' EXIT
mkdir "$LAYOUT/verified" "$LAYOUT/lists"
cp "$TGZ" "$LAYOUT/verified/"
basename "$TGZ" > "$LAYOUT/lists/npm.txt"
echo "== 1. npm publish --dry-run (from a directory laid out like the workflow's, with the workflow's own ./verified/ argument)"
NPM_OUT=$( cd "$LAYOUT" && npm publish "./verified/$(cat lists/npm.txt)" --dry-run --access public --ignore-scripts --tag "$TAG" 2>&1 ) || { printf '%s\n' "$NPM_OUT" >&2; die "npm publish --dry-run failed"; }
printf '%s\n' "$NPM_OUT" | tail -8
# the lines npm 10 and 11 both print: the tarball's name and version, and that this was a dry run
printf '%s\n' "$NPM_OUT" | grep -qF "name: @airplanemode/glyphsift" || die "npm's dry run did not name the package @airplanemode/glyphsift"
printf '%s\n' "$NPM_OUT" | grep -qE "version: $VERSION\$" || die "npm's dry run did not name version $VERSION"
printf '%s\n' "$NPM_OUT" | grep -qF "(dry-run)" || die "npm's output does not say it was a dry run: nothing may be published here"

echo "== 2. cargo publish --dry-run --workspace --locked --no-verify (the workflow's command with --dry-run: nothing is compiled)"
DIRTY=()
if [ "${REHEARSE_ALLOW_DIRTY:-0}" = 1 ]; then DIRTY=(--allow-dirty); fi
CARGO_OUT=$( ( unset RUSTFLAGS; cargo publish --dry-run --workspace --locked --no-verify ${DIRTY[@]+"${DIRTY[@]}"} ) 2>&1 ) || { printf '%s\n' "$CARGO_OUT" >&2; die "cargo publish --dry-run failed"; }
CARGO_PLAIN=$(printf '%s\n' "$CARGO_OUT" | LC_ALL=C sed -e "s/$(printf '\033')\\[[0-9;]*[A-Za-z]//g" -e "s/$(printf '\r')\$//")
printf '%s\n' "$CARGO_PLAIN" | tail -8
for c in glyphsift-core glyphsift-cli; do
  printf '%s\n' "$CARGO_PLAIN" | grep -qE "^ *Uploading $c v$VERSION " || die "the dry run did not reach the upload step of $c"
done
[ "$(printf '%s\n' "$CARGO_PLAIN" | grep -c 'aborting upload due to dry run')" -ge 2 ] || die "cargo's dry run did not abort both uploads"
if printf '%s\n' "$CARGO_PLAIN" | grep -qE "^ *Uploading glyphsift-(py|wasm) "; then die "a publish = false crate reached the upload step"; fi

echo "== 3. wheel metadata on every wheel in the directory"
N=0
for w in "$DIR"/glyphsift-"$VERSION"-*.whl; do
  [ -f "$w" ] || continue
  "$PY" -I tests/python/check_wheel.py "$(to_native "$w")" "$VERSION" | tail -1
  N=$((N+1))
done
[ "$N" -ge 1 ] || die "no wheel in the release directory"
echo "publish-dry-run: ok ($N wheel(s), the tarball, both crates); nothing was published"
