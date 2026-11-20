#!/usr/bin/env bash
# D3-03: the checks the publish workflow runs before it publishes (scripts/release/publish-guard.sh) fail closed. Nobody runs publish.yml before the
# owner does, so every refusal path is proved here with stand-ins for the two network tools (a fake `gh` and a fake `curl` first on PATH) and
# scratch copies of the files the guard reads. No network, no secret, no runner variable: the guard takes GUARD_* values and RELEASE_KEY_ID in.
#
#   tests/scripts/publish-guard.sh
#
#  A. dist-tag: no pre-release identifier gives latest; alpha, beta and rc give themselves; any other identifier or build metadata is refused.
#  B. version: read from Cargo.toml's [workspace.package]; an invalid one is refused.
#  B2. armed (lock 3): RELEASE_PUBLISH_ARMED must be exactly the word true; anything else, or unset, is refused.
#  C. key-id (lock 6, S1-129): RELEASE_KEY_ID must be 64 lowercase hex and equal the one key in docs/release-keys.json; none, two, a mismatch, a
#     missing variable or a malformed file is refused.
#  D. tag-binding: tag v<version> must peel (annotated tags followed) to GUARD_SHA; a different commit, a missing tag or a tag of a tree is refused.
#  E. manifest-binding: version, id glyphsift-release, publisher, no expiresAt, at least one signature; each way to differ is refused.
#  F. registry-absent: npm, PyPI and crates.io must each answer 404; 200, 5xx and a failed request are all refused (fail closed).
#  G. exact-set: the verified directory holds exactly the manifest, SHA256SUMS, the tarball, the sdist, the two crates and one wheel per platform.
#  H. crate-digests: the re-packaged crates equal the digests in the verified manifest.
#  I. crate-index (FR1, BUG-S1-S7-03 / S1-131): after `cargo publish`, crates.io's sparse index must show glyphsift-core and glyphsift-cli at this version
#     with the cksum the signed manifest lists; absence and server trouble are retried for 10 minutes (then refused), a different cksum, a yanked entry,
#     two entries or a malformed index line is refused at once.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
GUARD=$REPO/scripts/release/publish-guard.sh
[ -f "$GUARD" ] || { fail "scripts/release/publish-guard.sh exists"; finish; exit $?; }
command -v node >/dev/null || { fail "node not found: publish-guard.sh needs Node 22"; finish; exit 1; }
S=$(mktemp -d "${TMPDIR:-/tmp}/publish-guard-test.XXXXXX")
S=$(cd "$S" && pwd -P)
cleanup() { case "$S" in /*/publish-guard-test.??????) rm -rf "$S" ;; esac; }
trap cleanup EXIT

# run <expected exit> <name> <command...>: the command runs in the scratch repository $S/repo with the fakes first on PATH
mkdir -p "$S/repo/docs" "$S/repo/scripts/release" "$S/bin"
cp "$GUARD" "$S/repo/scripts/release/publish-guard.sh"
G="bash $S/repo/scripts/release/publish-guard.sh"
printf '[workspace.package]\nversion = "0.1.3"\nedition = "2024"\n' > "$S/repo/Cargo.toml"
KEYID=$(printf 'a%.0s' $(seq 1 64))
OTHER=$(printf 'b%.0s' $(seq 1 64))
cat > "$S/repo/docs/release-keys.json" <<JSON
{"spec":"airplanemode.release-keys/0.1","keys":[{"keyId":"$KEYID","publicKey":"11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="}]}
JSON
# the fake gh: GH_FAKE_REF is "<type> <sha>" for refs/tags, GH_FAKE_TAG is "<type> <sha>" for the annotated tag object; GH_FAKE_FAIL=1 fails
cat > "$S/bin/gh" <<'SH'
#!/usr/bin/env bash
[ "${GH_FAKE_FAIL:-0}" = 1 ] && { echo "gh: HTTP 404" >&2; exit 1; }
case "$2" in
  */git/ref/tags/*) echo "${GH_FAKE_REF:-}" ;;
  */git/tags/*) echo "${GH_FAKE_TAG:-}" ;;
  *) exit 2 ;;
esac
SH
# the fake curl: prints the http code in CURL_FAKE_CODES (space separated, one per call); CURL_FAKE_FAIL=1 simulates a failed request (code 000, exit 6).
# Every call's arguments are appended to $CURL_FAKE_STATE.args. A request to index.crates.io is answered from $CURL_FAKE_INDEXDIR/<crate>/<k>.code and <k>.body,
# where k counts the requests for that crate (the last file repeats), and the body is written to the -o file; a crate with no files answers 404.
cat > "$S/bin/curl" <<'SH'
#!/usr/bin/env bash
n=$(cat "$CURL_FAKE_STATE" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$CURL_FAKE_STATE"
echo "$*" >> "$CURL_FAKE_STATE.args"
out=""; prev=""; url=""
for a in "$@"; do [ "$prev" = -o ] && out=$a; prev=$a; url=$a; done
if [ "${CURL_FAKE_FAIL:-0}" = 1 ]; then printf '000'; exit 6; fi
case "$url" in
  https://index.crates.io/*)
    crate=${url##*/}; d=$CURL_FAKE_INDEXDIR/$crate
    k=$(cat "$d.count" 2>/dev/null || echo 0); k=$((k+1)); echo "$k" > "$d.count"
    while [ "$k" -gt 1 ] && [ ! -f "$d/$k.code" ]; do k=$((k-1)); done
    if [ -f "$d/$k.code" ]; then
      [ -n "$out" ] && { if [ -f "$d/$k.body" ]; then cp "$d/$k.body" "$out"; else : > "$out"; fi; }
      if [ "$(cat "$d/$k.code")" = fail ]; then printf '000'; exit 28; fi
      cat "$d/$k.code"; exit 0
    fi
    [ -n "$out" ] && : > "$out"; printf '404'; exit 0 ;;
esac
set -- $CURL_FAKE_CODES
eval "code=\${$n:-404}"
[ -n "$out" ] && : > "$out"
printf '%s' "$code"
SH
# the fake sleep: records the seconds and returns at once, so a 10-minute retry window is exercised in no time
cat > "$S/bin/sleep" <<'SH'
#!/usr/bin/env bash
echo "$1" >> "$SLEEP_FAKE_LOG"
SH
chmod +x "$S/bin/gh" "$S/bin/curl" "$S/bin/sleep"
export SLEEP_FAKE_LOG=$S/sleep.log CURL_FAKE_INDEXDIR=$S/index
export CURL_FAKE_STATE=$S/curl.state
run() { # <expected exit> <name> <command...>
  local want=$1 name=$2; shift 2
  local out rc
  out=$( cd "$S/repo" && PATH="$S/bin:$PATH" "$@" 2>&1 ); rc=$?
  if [ "$rc" = "$want" ]; then ok "$name (exit $rc)"; else fail "$name (want exit $want, got $rc): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"; fi
  LAST_OUT=$out
}
reset_curl() { rm -f "$CURL_FAKE_STATE" "$CURL_FAKE_STATE.args" "$SLEEP_FAKE_LOG"; rm -rf "$S/index"; mkdir -p "$S/index"; }

echo "== A. dist-tag"
for pair in "0.1.3:latest" "1.0.0:latest" "1.0.0-rc.1:rc" "1.0.0-rc:rc" "0.4.0-alpha.1:alpha" "0.3.0-beta.2:beta"; do
  v=${pair%%:*}; want=${pair#*:}
  got=$( cd "$S/repo" && $G dist-tag "$v" 2>/dev/null ); expect_eq "dist-tag $v is $want" "$want" "$got"
done
for v in 0.1.0-dev 1.0.0+build.5 1.0 v1.0.0 "" 1.0.0-next.1 ; do run 1 "dist-tag '$v' is refused" $G dist-tag "$v"; done

echo "== B. version"
got=$( cd "$S/repo" && $G version 2>/dev/null ); expect_eq "version reads 0.1.3 from Cargo.toml" 0.1.3 "$got"
cp "$S/repo/Cargo.toml" "$S/Cargo.toml.good"
printf '[workspace.package]\nversion = "0.1"\n' > "$S/repo/Cargo.toml"; run 1 "an invalid version is refused" $G version
printf '[package]\nversion = "0.1.3"\n' > "$S/repo/Cargo.toml"; run 1 "no [workspace.package] version is refused" $G version
cp "$S/Cargo.toml.good" "$S/repo/Cargo.toml"

echo "== B2. armed (lock 3)"
run 0 "RELEASE_PUBLISH_ARMED=true passes" env RELEASE_PUBLISH_ARMED=true $G armed
for v in "" false TRUE True 1 yes "true " " true"; do run 1 "RELEASE_PUBLISH_ARMED='$v' is refused" env RELEASE_PUBLISH_ARMED="$v" $G armed; done
run 1 "an unset RELEASE_PUBLISH_ARMED is refused" env -u RELEASE_PUBLISH_ARMED $G armed

echo "== C. key-id (lock 6)"
run 0 "RELEASE_KEY_ID equal to the one committed key passes" env RELEASE_KEY_ID="$KEYID" $G key-id
run 1 "a different key id is refused" env RELEASE_KEY_ID="$OTHER" $G key-id
run 1 "an unset RELEASE_KEY_ID is refused" env -u RELEASE_KEY_ID $G key-id
run 1 "an empty RELEASE_KEY_ID is refused" env RELEASE_KEY_ID= $G key-id
run 1 "an upper-case key id is refused" env RELEASE_KEY_ID="$(printf '%s' "$KEYID" | tr a-f A-F)" $G key-id
run 1 "a short key id is refused" env RELEASE_KEY_ID=abc $G key-id
cp "$S/repo/docs/release-keys.json" "$S/release-keys.good"
printf '{"spec":"airplanemode.release-keys/0.1","keys":[]}\n' > "$S/repo/docs/release-keys.json"; run 1 "an empty keys list is refused" env RELEASE_KEY_ID="$KEYID" $G key-id
printf '{"spec":"airplanemode.release-keys/0.1","keys":[{"keyId":"%s","publicKey":"x"},{"keyId":"%s","publicKey":"y"}]}\n' "$KEYID" "$OTHER" > "$S/repo/docs/release-keys.json"; run 1 "two keys are refused (one key signs releases)" env RELEASE_KEY_ID="$KEYID" $G key-id
printf 'not json' > "$S/repo/docs/release-keys.json"; run 1 "a malformed file is refused" env RELEASE_KEY_ID="$KEYID" $G key-id
cp "$S/release-keys.good" "$S/repo/docs/release-keys.json"

echo "== D. tag-binding"
SHA=$(printf 'c%.0s' $(seq 1 40)); TAGOBJ=$(printf 'd%.0s' $(seq 1 40)); OTHERSHA=$(printf 'e%.0s' $(seq 1 40))
T="env GH_TOKEN=x GUARD_REPO=AirplaneMode-Labs/glyphsift GUARD_VERSION=0.1.3 GUARD_SHA=$SHA"
run 0 "a lightweight tag at the built commit passes" $T GH_FAKE_REF="commit $SHA" $G tag-binding
run 0 "an annotated tag peeled to the built commit passes" $T GH_FAKE_REF="tag $TAGOBJ" GH_FAKE_TAG="commit $SHA" $G tag-binding
run 1 "a tag at a different commit is refused" $T GH_FAKE_REF="commit $OTHERSHA" $G tag-binding
run 1 "an annotated tag peeled to a different commit is refused" $T GH_FAKE_REF="tag $TAGOBJ" GH_FAKE_TAG="commit $OTHERSHA" $G tag-binding
run 1 "a missing tag (gh fails) is refused" $T GH_FAKE_FAIL=1 $G tag-binding
run 1 "a tag that points at a tree is refused" $T GH_FAKE_REF="tree $SHA" $G tag-binding
run 1 "an empty answer is refused" $T GH_FAKE_REF="" $G tag-binding
run 1 "an unset GUARD_SHA is refused" env -u GUARD_SHA GH_TOKEN=x GUARD_REPO=AirplaneMode-Labs/glyphsift GUARD_VERSION=0.1.3 GH_FAKE_REF="commit $SHA" $G tag-binding
run 1 "a malformed GUARD_SHA is refused" env GH_TOKEN=x GUARD_REPO=AirplaneMode-Labs/glyphsift GUARD_VERSION=0.1.3 GUARD_SHA=zz GH_FAKE_REF="commit $SHA" $G tag-binding
run 1 "a repository that is not this one is refused" env GH_TOKEN=x GUARD_REPO=someone/else GUARD_VERSION=0.1.3 GUARD_SHA=$SHA GH_FAKE_REF="commit $SHA" $G tag-binding

echo "== E. manifest-binding"
mk() { # <version> <id> <publisher> <expiresAt or ''> <signatures json>
  local exp=""; [ -n "$4" ] && exp=",\"expiresAt\":\"$4\""
  printf '{"spec":"airplanemode.manifest/0.1","id":"%s","version":"%s","publisher":"%s","createdAt":"2026-11-20T00:00:00Z"%s,"entries":[],"signatures":%s}\n' "$2" "$1" "$3" "$exp" "$5" > "$S/m.json"
}
SIG='[{"alg":"ed25519","keyId":"x","sig":"y","signedAt":"2026-11-20T00:00:00Z"}]'
mk 0.1.3 glyphsift-release "Airplane Mode Labs" "" "$SIG"; run 0 "the matching signed manifest passes" env GUARD_VERSION=0.1.3 $G manifest-binding "$S/m.json"
mk 0.1.4 glyphsift-release "Airplane Mode Labs" "" "$SIG"; run 1 "another version is refused" env GUARD_VERSION=0.1.3 $G manifest-binding "$S/m.json"
mk 0.1.3 glyphsift-rehearsal "Airplane Mode Labs" "" "$SIG"; run 1 "a rehearsal id is refused" env GUARD_VERSION=0.1.3 $G manifest-binding "$S/m.json"
mk 0.1.3 pagetriage-release "Airplane Mode Labs" "" "$SIG"; run 1 "another package's release id is refused" env GUARD_VERSION=0.1.3 $G manifest-binding "$S/m.json"
mk 0.1.3 glyphsift-release "Someone Else" "" "$SIG"; run 1 "another publisher is refused" env GUARD_VERSION=0.1.3 $G manifest-binding "$S/m.json"
mk 0.1.3 glyphsift-release "Airplane Mode Labs" "2027-11-20T00:00:00Z" "$SIG"; run 1 "an expiresAt is refused (TD-121)" env GUARD_VERSION=0.1.3 $G manifest-binding "$S/m.json"
mk 0.1.3 glyphsift-release "Airplane Mode Labs" "" "[]"; run 1 "an unsigned manifest is refused" env GUARD_VERSION=0.1.3 $G manifest-binding "$S/m.json"
printf '{"id":' > "$S/m.json"; run 1 "a malformed manifest is refused" env GUARD_VERSION=0.1.3 $G manifest-binding "$S/m.json"
run 1 "a missing manifest is refused" env GUARD_VERSION=0.1.3 $G manifest-binding "$S/none.json"

echo "== F. registry-absent"
reset_curl; run 0 "three 404 answers pass" env GUARD_VERSION=0.1.3 CURL_FAKE_CODES="404 404 404" $G registry-absent
reset_curl; run 1 "npm already holds the version (200)" env GUARD_VERSION=0.1.3 CURL_FAKE_CODES="200 404 404" $G registry-absent
reset_curl; run 1 "PyPI already holds the version (200)" env GUARD_VERSION=0.1.3 CURL_FAKE_CODES="404 200 404" $G registry-absent
reset_curl; run 1 "crates.io already holds the version (200)" env GUARD_VERSION=0.1.3 CURL_FAKE_CODES="404 404 200" $G registry-absent
reset_curl; run 1 "a 500 is not 'absent' (fail closed)" env GUARD_VERSION=0.1.3 CURL_FAKE_CODES="404 500 404" $G registry-absent
reset_curl; run 1 "a 403 is not 'absent' (fail closed)" env GUARD_VERSION=0.1.3 CURL_FAKE_CODES="403 404 404" $G registry-absent
reset_curl; run 1 "a failed request is not 'absent' (fail closed)" env GUARD_VERSION=0.1.3 CURL_FAKE_FAIL=1 $G registry-absent
reset_curl; run 1 "an invalid version is refused before any lookup" env GUARD_VERSION=0.1 CURL_FAKE_CODES="404 404 404" $G registry-absent

echo "== G. exact-set"
V=0.1.3
mkset() {
  rm -rf "$S/verified"; mkdir -p "$S/verified"
  for f in release-manifest.json SHA256SUMS "airplanemode-glyphsift-$V.tgz" "glyphsift-$V.tar.gz" "glyphsift-core-$V.crate" "glyphsift-cli-$V.crate" \
    "glyphsift-$V-cp39-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64.whl" "glyphsift-$V-cp39-abi3-macosx_11_0_arm64.whl" "glyphsift-$V-cp39-abi3-win_amd64.whl"; do
    printf 'x\n' > "$S/verified/$f"
  done
}
mkset; run 0 "the exact expected set passes" env GUARD_VERSION=$V $G exact-set "$S/verified" "$S/lists"
for l in npm pypi; do [ -f "$S/lists/$l.txt" ] && ok "exact-set wrote $l.txt" || fail "exact-set wrote $l.txt"; done
expect_eq "the npm list is exactly the tarball" "airplanemode-glyphsift-$V.tgz" "$(cat "$S/lists/npm.txt" 2>/dev/null)"
expect_eq "the PyPI list is the sdist and three wheels, sorted" 4 "$(wc -l < "$S/lists/pypi.txt" 2>/dev/null | tr -d ' ')"
expect_eq "the PyPI list names no crate and no tarball" 0 "$(grep -cE '\.crate|\.tgz' "$S/lists/pypi.txt" 2>/dev/null)"
mkset; rm "$S/verified/glyphsift-$V-cp39-abi3-win_amd64.whl"; run 1 "a missing wheel is refused" env GUARD_VERSION=$V $G exact-set "$S/verified" "$S/lists"
mkset; printf 'x' > "$S/verified/extra.txt"; run 1 "an extra file is refused" env GUARD_VERSION=$V $G exact-set "$S/verified" "$S/lists"
mkset; printf 'x' > "$S/verified/glyphsift-$V-cp39-abi3-win32.whl"; run 1 "a fourth wheel is refused" env GUARD_VERSION=$V $G exact-set "$S/verified" "$S/lists"
mkset; run 1 "a different expected version is refused" env GUARD_VERSION=0.1.4 $G exact-set "$S/verified" "$S/lists"
mkset; rm "$S/verified/glyphsift-$V.tar.gz"; run 1 "a missing sdist is refused" env GUARD_VERSION=$V $G exact-set "$S/verified" "$S/lists"
mkset; mkdir "$S/verified/sub"; run 1 "a subdirectory is refused" env GUARD_VERSION=$V $G exact-set "$S/verified" "$S/lists"
mkset; ln -s "$S/verified/SHA256SUMS" "$S/verified/link.whl" 2>/dev/null && run 1 "a link is refused" env GUARD_VERSION=$V $G exact-set "$S/verified" "$S/lists"

echo "== H. crate-digests"
mkdir -p "$S/repo/target/package"
mkset
printf 'core-bytes' > "$S/repo/target/package/glyphsift-core-$V.crate"; printf 'cli-bytes' > "$S/repo/target/package/glyphsift-cli-$V.crate"
core_sha=$(node -e 'process.stdout.write(require("crypto").createHash("sha256").update("core-bytes").digest("hex"))')
cli_sha=$(node -e 'process.stdout.write(require("crypto").createHash("sha256").update("cli-bytes").digest("hex"))')
mkman() { printf '{"entries":[{"id":"glyphsift-core-%s.crate","sha256":"%s"},{"id":"glyphsift-cli-%s.crate","sha256":"%s"}]}\n' "$V" "$1" "$V" "$2" > "$S/verified/release-manifest.json"; }
mkman "$core_sha" "$cli_sha"; run 0 "re-packaged crates equal the manifest digests" env GUARD_VERSION=$V $G crate-digests "$S/verified" "$S/repo/target/package"
mkman "$cli_sha" "$cli_sha"; run 1 "a different core digest is refused" env GUARD_VERSION=$V $G crate-digests "$S/verified" "$S/repo/target/package"
mkman "$core_sha" "$core_sha"; run 1 "a different cli digest is refused" env GUARD_VERSION=$V $G crate-digests "$S/verified" "$S/repo/target/package"
rm "$S/repo/target/package/glyphsift-cli-$V.crate"; mkman "$core_sha" "$cli_sha"; run 1 "a missing re-packaged crate is refused" env GUARD_VERSION=$V $G crate-digests "$S/verified" "$S/repo/target/package"

echo "== I. crate-index (S1-131)"
core_line() { # <version> <cksum> [yanked]: one sparse-index line, as crates.io writes it (name, vers, deps, cksum, features, yanked)
  printf '{"name":"glyphsift-core","vers":"%s","deps":[],"cksum":"%s","features":{},"yanked":%s}\n' "$1" "$2" "${3:-false}"
}
cli_line() { printf '{"name":"glyphsift-cli","vers":"%s","deps":[{"name":"glyphsift-core","req":"^0.1.3"}],"cksum":"%s","features":{},"yanked":%s}\n' "$1" "$2" "${3:-false}"; }
idx() { # <crate> <k> <code> [body]: the k-th answer for a crate
  mkdir -p "$S/index/$1"; printf '%s' "$3" > "$S/index/$1/$2.code"; [ -n "${4-}" ] && printf '%s' "$4" > "$S/index/$1/$2.body"; true
}
total_slept() { if [ -f "$SLEEP_FAKE_LOG" ]; then awk '{s+=$1} END{print s+0}' "$SLEEP_FAKE_LOG"; else echo 0; fi; }
calls_for() { grep -c "index.crates.io/gl/yp/$1\$" "$CURL_FAKE_STATE.args" 2>/dev/null || true; }
mkman "$core_sha" "$cli_sha"
CI_G="env GUARD_VERSION=$V"
reset_curl; idx glyphsift-core 1 200 "$(core_line $V "$core_sha")"; idx glyphsift-cli 1 200 "$(cli_line $V "$cli_sha")"
run 0 "both crates in the index with the signed cksums pass" $CI_G $G crate-index "$S/verified"
expect_eq "no sleep when both are visible at once" 0 "$(total_slept)"
expect_eq "exactly one request per crate" "1 1" "$(calls_for glyphsift-core) $(calls_for glyphsift-cli)"
expect_eq "the request URLs are the sparse-index paths of the two crates, over https only, TLS 1.2, with the guard's user agent" 2 "$(grep -cE -- "--proto =https .*--tlsv1\.2 .* https://index\.crates\.io/gl/yp/glyphsift-(core|cli)\$" "$CURL_FAKE_STATE.args")"
expect_eq "no request goes anywhere but index.crates.io" 0 "$(grep -vc 'https://index\.crates\.io/gl/yp/' "$CURL_FAKE_STATE.args")"
# older lines of the same crate in the index do not matter, the line of this version does
reset_curl; idx glyphsift-core 1 200 "$(core_line 0.1.2 deadbeef)"$'\n'"$(core_line $V "$core_sha")"; idx glyphsift-cli 1 200 "$(cli_line $V "$cli_sha")"
run 0 "an older line before this version's line is ignored" $CI_G $G crate-index "$S/verified"
# propagation: not there yet (404), then a server error, then visible
reset_curl; idx glyphsift-core 1 404; idx glyphsift-core 2 503; idx glyphsift-core 3 200 "$(core_line $V "$core_sha")"; idx glyphsift-cli 1 200 "$(cli_line 0.1.2 deadbeef)"; idx glyphsift-cli 2 200 "$(cli_line $V "$cli_sha")"
run 0 "404, a 503 and a missing version line are retried until the crates are visible" $CI_G $G crate-index "$S/verified"
expect_eq "it slept between the attempts (15 seconds each, three rounds)" 30 "$(total_slept)"
expect_eq "core was asked three times, cli twice (a confirmed crate is not asked again)" "3 2" "$(calls_for glyphsift-core) $(calls_for glyphsift-cli)"
# never visible: the whole window is used, then it fails loudly
reset_curl
run 1 "a crate that never appears fails after the whole window" $CI_G $G crate-index "$S/verified"
expect_eq "the default window is 600 seconds (40 sleeps of 15 seconds)" 600 "$(total_slept)"
printf '%s\n' "$LAST_OUT" | grep -q 'publish-guard: ' && ok "the failure is a publish-guard message on stderr" || fail "the failure is a publish-guard message"
printf '%s\n' "$LAST_OUT" | grep -q 'glyphsift-core' && printf '%s\n' "$LAST_OUT" | grep -q '600 seconds' && ok "the message names the crate and the window" || fail "the message names the crate and the window: $(printf '%s' "$LAST_OUT" | tail -1)"
reset_curl; run 1 "a custom short window (timeout 30, interval 10) still fails when nothing appears" $CI_G $G crate-index "$S/verified" 30 10
expect_eq "the custom window slept 30 seconds in all" 30 "$(total_slept)"
reset_curl; run 1 "a failing request is retried and then refused (never counted as published)" env CURL_FAKE_FAIL=1 GUARD_VERSION=$V $G crate-index "$S/verified" 20 10
expect_eq "the failing requests slept 20 seconds in all" 20 "$(total_slept)"
reset_curl; idx glyphsift-core 1 200 "$(core_line $V "$core_sha")"; idx glyphsift-cli 1 fail
run 1 "a cli request that times out every time is refused after the window" $CI_G $G crate-index "$S/verified" 20 10
# a different checksum is never retried: the registry is immutable, the signed bytes are not what it holds
reset_curl; idx glyphsift-core 1 200 "$(core_line $V "$cli_sha")"; idx glyphsift-cli 1 200 "$(cli_line $V "$cli_sha")"
run 1 "core with a different cksum is refused" $CI_G $G crate-index "$S/verified"
expect_eq "a cksum mismatch is not retried (no sleep)" 0 "$(total_slept)"
printf '%s\n' "$LAST_OUT" | grep -q "$core_sha" && printf '%s\n' "$LAST_OUT" | grep -q "$cli_sha" && ok "the mismatch message prints both digests" || fail "the mismatch message prints both digests"
reset_curl; idx glyphsift-core 1 200 "$(core_line $V "$core_sha")"; idx glyphsift-cli 1 200 "$(cli_line $V "$core_sha")"
run 1 "cli with a different cksum is refused" $CI_G $G crate-index "$S/verified"
reset_curl; idx glyphsift-core 1 200 "$(core_line $V "$core_sha" true)"; idx glyphsift-cli 1 200 "$(cli_line $V "$cli_sha")"
run 1 "a yanked entry is refused" $CI_G $G crate-index "$S/verified"
reset_curl; idx glyphsift-core 1 200 "$(core_line $V "$core_sha")"$'\n'"$(core_line $V "$core_sha")"; idx glyphsift-cli 1 200 "$(cli_line $V "$cli_sha")"
run 1 "two lines for the same version are refused" $CI_G $G crate-index "$S/verified"
reset_curl; idx glyphsift-core 1 200 "not json at all"; idx glyphsift-cli 1 200 "$(cli_line $V "$cli_sha")"
run 1 "a malformed index line is refused" $CI_G $G crate-index "$S/verified"
reset_curl; idx glyphsift-core 1 200 "$(core_line $V "$(printf '%s' "$core_sha" | tr a-f A-F)")"; idx glyphsift-cli 1 200 "$(cli_line $V "$cli_sha")"
run 1 "the signed digest in upper case is not equal (the comparison is exact)" $CI_G $G crate-index "$S/verified"
# the manifest side
reset_curl; idx glyphsift-core 1 200 "$(core_line $V "$core_sha")"; idx glyphsift-cli 1 200 "$(cli_line $V "$cli_sha")"
printf '{"entries":[{"id":"glyphsift-core-%s.crate","sha256":"%s"}]}\n' "$V" "$core_sha" > "$S/verified/release-manifest.json"
run 1 "a manifest without the cli crate is refused before any request" $CI_G $G crate-index "$S/verified"
expect_eq "no request was made" 0 "$(cat "$CURL_FAKE_STATE" 2>/dev/null || echo 0)"
printf '{"entries":[{"id":"glyphsift-core-%s.crate","sha256":"%s"},{"id":"glyphsift-cli-%s.crate","sha256":"nothex"}]}\n' "$V" "$core_sha" "$V" > "$S/verified/release-manifest.json"
reset_curl; run 1 "a manifest digest that is not 64 hex characters is refused" $CI_G $G crate-index "$S/verified"
mkman "$core_sha" "$cli_sha"
run 1 "an unset GUARD_VERSION is refused" env -u GUARD_VERSION $G crate-index "$S/verified"
run 1 "a missing manifest directory is refused" $CI_G $G crate-index "$S/nowhere"
for bad in "abc" "-5" "0" "601" "1.5" ""; do reset_curl; run 1 "a window of '$bad' seconds is refused" $CI_G $G crate-index "$S/verified" "$bad"; done
reset_curl; run 1 "an interval of 0 is refused (it would never wait)" $CI_G $G crate-index "$S/verified" 60 0
reset_curl; run 1 "an interval above the window is refused" $CI_G $G crate-index "$S/verified" 60 61

finish
