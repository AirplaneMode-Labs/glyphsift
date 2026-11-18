#!/usr/bin/env bash
# Tests for scripts/release-manifest.mjs: an unsigned airplanemode.manifest/0.1 for the release artifacts (the wheel
# and the npm tarball). Runs against a scratch copy of the layout (scripts/, scripts/lib/, Cargo.toml, dist/), so the
# real tree is untouched. Written before the script (red-D3-09.log); extended in Sprint 5 fix round 1 (TD-53) with the
# containment cases below (red/D3-FIX1-02-release-manifest-sh.log).
#
# The script is the same contract as pagetriage's scripts/release-manifest.mjs; only the constants at its top differ
# (id, licence), and these tests check exactly those two. The --out containment rules themselves (every Windows path
# form) are unit-tested in confine.test.mjs with path.win32 and an in-memory volume; this file runs the real script
# against real links, hard links and (on Windows) a real junction.
#
# Symlinks: on Windows (Git Bash) `ln -s` silently COPIES unless MSYS=winsymlinks:nativestrict, which is how pagetriage's
# windows-latest run 43667700010 never exercised the containment code. With it, `ln -s` makes a native link or fails.
# Every link made here is asserted with [ -L ], and a link that cannot be made FAILS the run: containment would be
# unproven. Nothing in this file is skipped; a case that does not apply to this OS prints "na" and why.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
export MSYS=winsymlinks:nativestrict

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ON_WINDOWS=1; OSNAME=windows ;;
  *) ON_WINDOWS=0; OSNAME=$(uname -s | tr 'A-Z' 'a-z') ;;
esac

command -v node >/dev/null || { fail "node not found: release-manifest.mjs cannot be tested (Node 22 is required)"; finish; exit 1; }
SCRATCH=$(mktemp -d)
cleanup() {
  # a junction is removed with rmdir (it removes the junction only) before the recursive delete
  if [ "$ON_WINDOWS" = 1 ] && [ -d "$SCRATCH/dist/junc" ]; then
    MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 cmd /c rmdir "$(cygpath -w "$SCRATCH/dist/junc")" >/dev/null 2>&1
  fi
  rm -rf "$SCRATCH"
}
trap cleanup EXIT
mkdir -p "$SCRATCH/scripts/lib" "$SCRATCH/dist" "$SCRATCH/art" "$SCRATCH/outside"
cp "$SCRIPTS_DIR/release-manifest.mjs" "$SCRATCH/scripts/" 2>/dev/null
cp "$SCRIPTS_DIR/lib/confine.mjs" "$SCRATCH/scripts/lib/" 2>/dev/null
cp "$REPO/Cargo.toml" "$SCRATCH/Cargo.toml"
VERSION=$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' "$REPO/Cargo.toml" | head -1)
printf 'wheel bytes\n' > "$SCRATCH/art/Glyphsift-0.1.0-cp39-abi3-macosx_11_0_arm64.whl"
head -c 4096 /dev/zero | tr '\0' 'x' > "$SCRATCH/art/airplanemode-glyphsift-0.1.0.tgz"
printf 'x' > "$SCRATCH/art/a b.tgz"
sha() { if command -v shasum >/dev/null; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
rm_run() { ( cd "$SCRATCH" && env "$@" >/dev/null 2>"$SCRATCH/last.err"; echo $? ); }
# rc_check <name> <want exit code> <command...>: like expect_eq on rm_run, and prints the script's stderr when it differs,
# so a failure on a runner nobody can see names its cause in the log.
rc_check() {
  local name=$1 want=$2 got; shift 2
  got=$(rm_run "$@")
  if [ "$want" = "$got" ]; then ok "$name"; else fail "$name (want '$want', got '$got')"; echo "      stderr: $(head -c 600 "$SCRATCH/last.err" | tr '\n' ' ')"; fi
}
# clean_error <name> <command...>: a non-zero exit, one line on stderr, and no stack trace (no "    at " frame, no node:internal).
clean_error() {
  local name=$1 got; shift
  got=$(rm_run "$@")
  local lines; lines=$(grep -c . "$SCRATCH/last.err" | tr -d ' ')
  if [ "$got" != 0 ] && ! grep -qE '^[[:space:]]+at |node:internal|^node:' "$SCRATCH/last.err" && [ "$lines" = 1 ]; then ok "$name"
  else fail "$name (exit '$got', $lines stderr lines, want non-zero, one line, no stack trace)"; echo "      stderr: $(head -c 400 "$SCRATCH/last.err" | tr '\n' ' ')"; fi
}
na() { echo "na   - $1"; }
# mklink <target> <link>: ln -s, then [ -L ]. A link that cannot be made is a FAILURE, never a skip.
mklink() {
  local err; err=$(ln -s "$1" "$2" 2>&1)
  if [ -L "$2" ]; then ok "[ -L ] after ln -s: ${2#"$SCRATCH"/}"; return 0; fi
  fail "could not create a symlink: containment unproven on this runner (${2#"$SCRATCH"/}: $err)"
  return 1
}
# mkhard <existing> <link>: ln (a hard link), then the link count of the file must be 2 or more. A name that cannot be made is a FAILURE.
mkhard() {
  local err n; err=$(ln "$1" "$2" 2>&1)
  n=$(node -e 'process.stdout.write(String(require("fs").statSync(process.argv[1]).nlink))' "$(npath "$1")" 2>/dev/null)
  if [ -n "$n" ] && [ "$n" -ge 2 ] 2>/dev/null; then ok "link count $n after ln: ${2#"$SCRATCH"/}"; return 0; fi
  fail "could not create a hard link: containment unproven on this runner (${2#"$SCRATCH"/}: $err)"
  return 1
}
# npath <posix path>: the native spelling on Windows (backslashes, drive letter), unchanged elsewhere.
npath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
RM="node scripts/release-manifest.mjs"
W=art/Glyphsift-0.1.0-cp39-abi3-macosx_11_0_arm64.whl
T=art/airplanemode-glyphsift-0.1.0.tgz

expect_eq "valid run exits 0" 0 "$(rm_run SOURCE_DATE_EPOCH=1700000000 $RM --out dist/m.json $T $W)"
cat > "$SCRATCH/check.mjs" <<'JS'
import { readFileSync } from "node:fs";
const [, , file, version, shaW, shaT, sizeT] = process.argv;
const m = JSON.parse(readFileSync(file, "utf8"));
const errs = [];
const eq = (n, a, b) => { if (JSON.stringify(a) !== JSON.stringify(b)) errs.push(`${n}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`); };
eq("spec", m.spec, "airplanemode.manifest/0.1");
eq("id", m.id, "glyphsift-release");
eq("version", m.version, version);
eq("publisher", m.publisher, "Airplane Mode Labs");
eq("createdAt", m.createdAt, "2023-11-14T22:13:20Z");
eq("signatures", m.signatures, []);
eq("keys", Object.keys(m).sort(), ["createdAt", "entries", "id", "publisher", "signatures", "spec", "version"]);
const ids = m.entries.map((e) => e.id);
eq("sorted ids", ids, [...ids].sort());
eq("unique ids", new Set(ids).size, ids.length);
eq("ids", ids, ["airplanemode-glyphsift-0.1.0.tgz", "glyphsift-0.1.0-cp39-abi3-macosx_11_0_arm64.whl"]);
const [t, w] = m.entries;
eq("wheel sha", w.sha256, shaW);
eq("tgz sha", t.sha256, shaT);
eq("tgz size", t.size, Number(sizeT));
for (const e of m.entries) {
  eq("entry keys " + e.id, Object.keys(e).sort(), ["id", "kind", "licence", "mediaType", "minProfile", "sha256", "size", "url", "version"]);
  eq("kind", e.kind, "other"); eq("licence", e.licence, "Apache-2.0"); eq("minProfile", e.minProfile, {});
  eq("url is the basename", e.url, e.id.length ? e.url : "");
  if (!/^[a-z0-9][a-z0-9._-]{0,127}$/.test(e.id)) errs.push("bad id " + e.id);
  if (!/^[0-9a-f]{64}$/.test(e.sha256)) errs.push("bad sha " + e.sha256);
  if (/[?#:]/.test(e.url)) errs.push("url has query, fragment or scheme: " + e.url);
  eq("version", e.version, version);
}
if (errs.length) { console.error(errs.join("\n")); process.exit(1); }
JS
expect_eq "manifest content valid, sorted, hashes equal shasum" 0 "$(cd "$SCRATCH" && node check.mjs dist/m.json "$VERSION" "$(sha "$SCRATCH/$W")" "$(sha "$SCRATCH/$T")" 4096 >/dev/null 2>&1; echo $?)"
expect_eq "the version is the Cargo.toml workspace version" 1 "$(grep -c "\"version\": \"$VERSION\"" "$SCRATCH/dist/m.json" | awk '{print ($1 >= 1) ? 1 : 0}')"
expect_eq "ends with one newline, no CR" "1" "$(tail -c1 "$SCRATCH/dist/m.json" | wc -l | tr -d ' ')"
rm_run SOURCE_DATE_EPOCH=1700000000 $RM --out dist/m2.json $W $T >/dev/null
expect_eq "argument order does not change the bytes" "$(sha "$SCRATCH/dist/m.json")" "$(sha "$SCRATCH/dist/m2.json")"
expect_eq "SOURCE_DATE_EPOCH 253402300799 accepted" 0 "$(rm_run SOURCE_DATE_EPOCH=253402300799 $RM --out dist/max.json $T)"
expect_eq "max epoch is 9999-12-31T23:59:59Z" 1 "$(grep -c '"createdAt": "9999-12-31T23:59:59Z"' "$SCRATCH/dist/max.json")"
expect_eq "SOURCE_DATE_EPOCH 0 accepted" 0 "$(rm_run SOURCE_DATE_EPOCH=0 $RM --out dist/zero.json $T)"
expect_eq "no SOURCE_DATE_EPOCH (now) accepted" 0 "$(cd "$SCRATCH" && env -u SOURCE_DATE_EPOCH $RM --out dist/now.json $T >/dev/null 2>&1; echo $?)"

for bad in 1e9 -1 253402300800 "" " 5" 0x10 1.5 99999999999999999999999 abc; do
  expect_eq "SOURCE_DATE_EPOCH '$bad' refused" 2 "$(rm_run "SOURCE_DATE_EPOCH=$bad" $RM --out dist/bad.json $T)"
done
expect_eq "no output file after a refused epoch" no "$([ -e "$SCRATCH/dist/bad.json" ] && echo yes || echo no)"

rc_check "'../x' out refused" 2 $RM --out ../x.json $T
rc_check "'dist/../x' out refused" 2 $RM --out dist/../x.json $T
rc_check "'dist\\..\\x' out refused (backslash spelling of '..')" 2 $RM --out 'dist\..\x.json' $T
rc_check "out outside dist/ refused" 2 $RM --out out.json $T
rc_check "absolute out outside dist/ refused" 2 $RM --out "$SCRATCH/outside/x.json" $T
rc_check "absolute out inside dist/ accepted" 0 $RM --out "$SCRATCH/dist/abs.json" $T
rc_check "nested new dir inside dist/ accepted" 0 $RM --out dist/sub/dir/n.json $T
rc_check "--out dist (the directory itself) refused" 2 $RM --out dist $T
mkdir -p "$SCRATCH/dist/adir"
rc_check "--out that is an existing directory refused" 2 $RM --out dist/adir $T
expect_eq "no temporary file left in dist/ after the runs above" 0 "$(ls -A "$SCRATCH/dist" | grep -c '^\.release-manifest-.*\.tmp$')"

# The same directory spelled with different letter case. On a case-insensitive volume (Windows, default macOS) both
# spellings are one directory, so a string compare of two spellings refuses a path that is inside dist/. This is the
# mechanism that reproduces on macOS the failure pagetriage saw on windows-latest ("absolute out inside dist/
# accepted (want 0, got 2)") and that T2 found in glyphsift's copy (DIST/x.json refused); the pre-fix script gives exit
# 2 here. A case-sensitive volume has no such alias, so it is not applicable.
if [ -d "$SCRATCH/DIST" ]; then
  rc_check "absolute out inside dist/ in different letter case accepted (case-insensitive volume)" 0 $RM --out "$SCRATCH/DIST/case.json" $T
  rc_check "relative out inside dist/ in different letter case accepted (case-insensitive volume)" 0 $RM --out DIST/case2.json $T
  expect_eq "the case-spelled manifest landed in dist/" yes "$([ -f "$SCRATCH/dist/case.json" ] && echo yes || echo no)"
else
  na "different letter case of dist/: not applicable on $OSNAME (this volume is case-sensitive, so DIST is another directory)"
fi

# Absolute --out in the spellings a Windows runner produces. Elsewhere these are covered by confine.test.mjs (path.win32).
if [ "$ON_WINDOWS" = 1 ]; then
  WDIST=$(npath "$SCRATCH/dist")
  rc_check "absolute out inside dist/, backslash spelling (cygpath -w)" 0 $RM --out "$WDIST\\w.json" $T
  rc_check "absolute out inside dist/, forward-slash spelling (cygpath -m)" 0 $RM --out "$(cygpath -m "$SCRATCH/dist")/m.json" $T
  rc_check "absolute out inside dist/, lower-case drive letter" 0 $RM --out "$(printf '%s' "$WDIST" | awk '{print tolower(substr($0,1,1)) substr($0,2)}')\\l.json" $T
  rc_check "absolute out inside dist/, 8.3 short-name spelling (cygpath -d)" 0 $RM --out "$(cygpath -d "$SCRATCH/dist")\\s.json" $T
  rc_check "extended-length prefix refused" 2 $RM --out "\\\\?\\$WDIST\\e.json" $T
  rc_check "alternate data stream refused" 2 $RM --out "$WDIST\\x.json:evil" $T
  rc_check "reserved device name refused" 2 $RM --out dist/NUL $T
else
  na "Windows path spellings (backslashes, drive-letter case, 8.3 names, \\\\?\\, streams, device names): not applicable on $OSNAME; unit-tested with path.win32 in confine.test.mjs"
fi

# Errors that are not refusals must still be one line, never a stack trace (T2: a file used as a directory, a name too long).
printf '{}\n' > "$SCRATCH/dist/real.json"
clean_error "a regular file used as a directory gives one line and no stack trace" $RM --out dist/real.json/x.json $T
LONG=$(head -c 300 /dev/zero | tr '\0' 'n')
clean_error "a 300-character file name gives one line and no stack trace" $RM --out "dist/$LONG" $T

# Links. The target file exists before the file link is made (a Windows file link to a missing target is a different test).
: > "$SCRATCH/outside/target.json"
if mklink "$SCRATCH/outside" "$SCRATCH/dist/link"; then
  rc_check "--out through a symlink leaving dist/ refused" 2 $RM --out dist/link/x.json $T
  expect_eq "nothing written through the symlink" no "$([ -e "$SCRATCH/outside/x.json" ] && echo yes || echo no)"
  expect_eq "nothing but target.json behind the symlink" "target.json" "$(ls -A "$SCRATCH/outside")"
fi
if mklink "$SCRATCH/outside/target.json" "$SCRATCH/dist/filelink.json"; then
  rc_check "--out that is itself a symlink leaving dist/ refused" 2 $RM --out dist/filelink.json $T
  expect_eq "nothing written through the file symlink" 0 "$(wc -c < "$SCRATCH/outside/target.json" | tr -d ' ')"
  expect_eq "the file symlink is still a symlink" yes "$([ -L "$SCRATCH/dist/filelink.json" ] && echo yes || echo no)"
fi
# A symlink to a file INSIDE dist/ is refused too: the manifest is never written through a link (T2's R20, which the old
# script accepted and wrote through, changing the file the link points at).
if mklink "$SCRATCH/dist/real.json" "$SCRATCH/dist/inner.json"; then
  rc_check "--out that is a symlink to a file inside dist/ refused (never written through a link)" 2 $RM --out dist/inner.json $T
  expect_eq "the inner symlink target is unchanged" "{}" "$(cat "$SCRATCH/dist/real.json")"
  expect_eq "the inner symlink is still a symlink" yes "$([ -L "$SCRATCH/dist/inner.json" ] && echo yes || echo no)"
fi
# A hard link is an ordinary regular file to lstat, so it cannot be refused by looking at it. What must hold is that the
# other name's bytes are never touched: the script replaces the name inside dist/ (temporary file, then rename) and never
# opens the existing file for writing. T2's R34: the old script wrote through the link and changed a file outside dist/.
mkdir -p "$SCRATCH/outside2"
printf 'ORIGINAL2' > "$SCRATCH/outside2/t2.json"
if mkhard "$SCRATCH/outside2/t2.json" "$SCRATCH/dist/hard.json"; then
  rc_check "--out that is a second name of a file outside dist/ is accepted (the name is replaced)" 0 $RM --out dist/hard.json $T
  expect_eq "the file outside dist/ keeps its bytes (nothing written through the hard link)" "ORIGINAL2" "$(cat "$SCRATCH/outside2/t2.json")"
  expect_eq "dist/hard.json now holds the manifest" 1 "$(grep -c '"spec": "airplanemode.manifest/0.1"' "$SCRATCH/dist/hard.json")"
  expect_eq "nothing else appeared next to the outside file" "t2.json" "$(ls -A "$SCRATCH/outside2")"
fi
printf 'SECOND' > "$SCRATCH/dist/first-name.json"
if mkhard "$SCRATCH/dist/first-name.json" "$SCRATCH/dist/second-name.json"; then
  rc_check "--out that is one of two names inside dist/ is accepted" 0 $RM --out dist/second-name.json $T
  expect_eq "the other name inside dist/ keeps its bytes" "SECOND" "$(cat "$SCRATCH/dist/first-name.json")"
fi

# Junction (Windows only). `cmd /c mklink /J` run from Git Bash needs MSYS argument conversion turned off: with it on, MSYS rewrites
# the lone /J switch into a POSIX-root path (C:/Program Files/Git/J) and no junction is made (pagetriage BUG-T2-S5-01; the first
# version of this case would have failed on windows-latest whatever the code under test did). Because no Windows machine is at hand,
# a static check, which runs on every OS, pins that the mklink line carries both switches that turn the conversion off. A junction
# that cannot be made FAILS the run. The same junction case is repeated without a shell in confine.test.mjs (fs.symlinkSync(.., "junction")).
SELF="$(dirname "$0")/release-manifest.sh"
MK_LINE=$(grep -E 'cmd (//|/)c mklink' "$SELF" | grep -v '^ *#' | grep -v 'MK_LINE=' | grep -v 'grep -E' | head -1)
case "$MK_LINE" in
  *MSYS2_ARG_CONV_EXCL=*MSYS_NO_PATHCONV=1*|*MSYS_NO_PATHCONV=1*MSYS2_ARG_CONV_EXCL=*) ok "the mklink /J call carries MSYS2_ARG_CONV_EXCL and MSYS_NO_PATHCONV" ;;
  *) fail "the mklink /J call does not switch MSYS path conversion off (line: $MK_LINE)" ;;
esac
mkdir -p "$SCRATCH/outside3"
if [ "$ON_WINDOWS" = 1 ]; then
  JL=$(cygpath -w "$SCRATCH/dist/junc"); JT=$(cygpath -w "$SCRATCH/outside3")
  MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 cmd /c mklink /J "$JL" "$JT" >/dev/null 2>&1
  if [ ! -d "$SCRATCH/dist/junc" ]; then
    powershell.exe -NoProfile -Command "New-Item -ItemType Junction -Path '$JL' -Target '$JT'" >/dev/null 2>&1
  fi
  if fsutil reparsepoint query "$JL" >/dev/null 2>&1; then
    ok "junction exists as a reparse point (fsutil reparsepoint query)"
  else
    fail "junction was not created as a reparse point: containment unproven on this runner"
  fi
  : > "$SCRATCH/dist/junc/probe" 2>/dev/null
  if [ -e "$SCRATCH/outside3/probe" ]; then
    ok "junction made: a write into dist/junc lands in outside3"
    rm -f "$SCRATCH/outside3/probe"
    rc_check "--out through a junction leaving dist/ refused" 2 $RM --out dist/junc/x.json $T
    rc_check "--out that is itself a junction refused" 2 $RM --out dist/junc $T
    expect_eq "nothing written through the junction" "" "$(ls -A "$SCRATCH/outside3")"
  else
    fail "could not create a junction: containment unproven on this runner (cmd /c mklink /J)"
  fi
else
  na "junction case (cmd /c mklink /J, MSYS conversion off): not applicable on $OSNAME"
fi

expect_eq "no artifacts refused" 2 "$(rm_run $RM --out dist/e.json)"
expect_eq "missing --out refused" 2 "$(rm_run $RM $T)"
expect_eq "missing artifact refused" 2 "$(rm_run $RM --out dist/e.json art/nope.tgz)"
expect_eq "a directory as artifact refused" 2 "$(rm_run $RM --out dist/e.json art)"
expect_eq "artifact name that is not a valid id refused" 2 "$(rm_run $RM --out dist/e.json "art/a b.tgz")"
expect_eq "duplicate ids (case-folded) refused" 2 "$(rm_run $RM --out dist/e.json $W art/../art/Glyphsift-0.1.0-cp39-abi3-macosx_11_0_arm64.whl)"
expect_eq "unknown option refused" 2 "$(rm_run $RM --out dist/e.json --sign x $T)"
expect_eq "unknown option --key refused" 2 "$(rm_run $RM --out dist/e.json --key x $T)"

# The script cannot sign: no key or signing option, no key file reads.
expect_eq "script has no key or sign option" 0 "$(cat "$SCRIPTS_DIR/release-manifest.mjs" "$SCRIPTS_DIR/lib/confine.mjs" 2>/dev/null | grep -Ec -- '--(key|sign|secret|seed|priv)|\.secret|\.pem|createPrivateKey|sign\(')"
expect_eq "script has no dependencies (node: imports and its own lib/confine.mjs only)" 0 "$(cat "$SCRIPTS_DIR/release-manifest.mjs" "$SCRIPTS_DIR/lib/confine.mjs" 2>/dev/null | grep -E "^import|require\(" | grep -v "node:" | grep -vc '"\./lib/confine\.mjs"')"

# The glyphsift copy differs from pagetriage's in its constants only: id and licence (both pinned here).
expect_eq "constants: manifest id is glyphsift-release" 1 "$(grep -c '^const MANIFEST_ID = "glyphsift-release";' "$SCRIPTS_DIR/release-manifest.mjs" 2>/dev/null)"
expect_eq "constants: licence is Apache-2.0" 1 "$(grep -c '^const LICENCE = "Apache-2.0";' "$SCRIPTS_DIR/release-manifest.mjs" 2>/dev/null)"
expect_eq "constants: version comes from Cargo.toml" 1 "$(grep -c '^const VERSION_SOURCE = "Cargo.toml";' "$SCRIPTS_DIR/release-manifest.mjs" 2>/dev/null)"
finish
