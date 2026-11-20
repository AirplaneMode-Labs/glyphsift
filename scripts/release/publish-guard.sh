#!/usr/bin/env bash
# The checks .github/workflows/publish.yml runs before it publishes anything, and that scripts/release/publish-dry-run.sh shares (Sprint 7, D3-03;
# TD-105, TD-121, TD-123; security conditions S1-126 and S1-129). Every check fails closed: any doubt is exit 1 with one line on stderr.
# tests/scripts/publish-guard.sh proves each refusal with stand-ins for `gh` and `curl`; nobody runs the workflow before the owner does.
#
#   publish-guard.sh version                          print the workspace version from Cargo.toml (plain semver, no build metadata)
#   publish-guard.sh dist-tag <version>               print the npm dist-tag: alpha, beta, rc, or latest for a version with no pre-release part
#                                                     (any other pre-release identifier is refused: it must not land on 'latest' by accident)
#   publish-guard.sh armed                            lock 3: RELEASE_PUBLISH_ARMED (the release environment's variable, passed in by the workflow) is exactly the word true
#   publish-guard.sh key-id                           lock 6 (S1-129): RELEASE_KEY_ID (64 lower-case hex, from the release environment's variables)
#                                                     must equal the single key in docs/release-keys.json at the commit being published
#   publish-guard.sh tag-binding                      GUARD_REPO, GUARD_VERSION, GUARD_SHA: tag v<version> peels (annotated tags followed) to GUARD_SHA
#   publish-guard.sh manifest-binding <manifest>      GUARD_VERSION: the signed manifest says glyphsift-release, this version, the release publisher,
#                                                     no expiresAt (TD-121) and carries at least one signature
#   publish-guard.sh registry-absent                  GUARD_VERSION: npm, PyPI and crates.io (core and cli) each answer 404 for this version
#   publish-guard.sh exact-set <dir> <outdir>         GUARD_VERSION: <dir> holds exactly the manifest, SHA256SUMS, the tarball, the sdist, the two crates
#                                                     and one wheel each for manylinux x86_64, macOS arm64 and win_amd64, nothing else (regular files
#                                                     only); writes the exact per-registry lists npm.txt, pypi.txt, crates.txt and all.txt to <outdir>
#   publish-guard.sh crate-digests <dir> <pkgdir>     GUARD_VERSION: the re-packaged crates in <pkgdir> (target/package) have the sha256 the verified
#                                                     manifest in <dir> lists (S1-126, TD-123); run in the step right before `cargo publish`
#   publish-guard.sh crate-index <dir> [<window> [<interval>]]
#                                                     GUARD_VERSION: after `cargo publish`, crates.io's sparse index (https://index.crates.io/gl/yp/<crate>) lists
#                                                     glyphsift-core and glyphsift-cli at this version with the cksum the verified manifest in <dir> lists
#                                                     (S1-131). A crate that is not there yet (404, a server error, a failed request, no line for this version)
#                                                     is asked again every <interval> seconds (default 15) for <window> seconds (default 600, at most 600), then
#                                                     refused; a different cksum, a yanked entry, two lines for the version or a malformed line is refused at once
# The workflow passes GUARD_* and RELEASE_KEY_ID in its step env; this script reads no runner variable and no secret and never publishes.
set -euo pipefail
cd "$(dirname "$0")/../.."

die() { echo "publish-guard: $*" >&2; exit 1; }
REPO_NAME=AirplaneMode-Labs/glyphsift
SEMVER='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
check_semver() { [[ "${1:-}" =~ $SEMVER ]] || die "'${1:-}' is not a plain semantic version (build metadata is not allowed)"; }
need_version() { check_semver "${GUARD_VERSION:-}"; }
to_native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

cmd_version() {
  local v
  v=$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
  check_semver "$v"
  printf '%s\n' "$v"
}

cmd_dist_tag() {
  local v=${1:-} pre first
  check_semver "$v"
  case "$v" in
    *-*)
      pre=${v#*-}; first=${pre%%.*}
      case "$first" in alpha|beta|rc) printf '%s\n' "$first" ;; *) die "pre-release identifier '$first' is not alpha, beta or rc: refusing to pick a dist-tag" ;; esac ;;
    *) printf 'latest\n' ;;
  esac
}

cmd_armed() {
  [ "${RELEASE_PUBLISH_ARMED:-}" = true ] || die "RELEASE_PUBLISH_ARMED is not 'true': the owner has not armed this release"
  echo "ok: RELEASE_PUBLISH_ARMED is true"
}

cmd_key_id() {
  local id=${RELEASE_KEY_ID:-}
  [[ "$id" =~ ^[0-9a-f]{64}$ ]] || die "RELEASE_KEY_ID is unset or is not 64 lower-case hex characters"
  node -e '
    const fs = require("fs");
    let j;
    try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { console.error("publish-guard: docs/release-keys.json is not JSON"); process.exit(1); }
    if (!j || !Array.isArray(j.keys) || j.keys.length !== 1) { console.error("publish-guard: docs/release-keys.json must hold exactly one key"); process.exit(1); }
    if (typeof j.keys[0].keyId !== "string" || j.keys[0].keyId !== process.argv[2]) { console.error("publish-guard: RELEASE_KEY_ID is not the key committed in docs/release-keys.json"); process.exit(1); }
  ' "$(to_native docs/release-keys.json)" "$id"
}

cmd_tag_binding() {
  need_version
  [ "${GUARD_REPO:-}" = "$REPO_NAME" ] || die "GUARD_REPO is not $REPO_NAME"
  [[ "${GUARD_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || die "GUARD_SHA is unset or is not a 40-character commit id"
  local ref type sha i
  ref=$(gh api "repos/$GUARD_REPO/git/ref/tags/v$GUARD_VERSION" --jq '.object.type + " " + .object.sha') || die "tag v$GUARD_VERSION does not exist (or could not be read)"
  for i in 1 2 3 4 5; do
    type=${ref%% *}; sha=${ref##* }
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "unexpected answer for tag v$GUARD_VERSION"
    case "$type" in
      commit) [ "$sha" = "$GUARD_SHA" ] || die "tag v$GUARD_VERSION resolves to $sha, not to the commit being published ($GUARD_SHA)"; return 0 ;;
      tag) ref=$(gh api "repos/$GUARD_REPO/git/tags/$sha" --jq '.object.type + " " + .object.sha') || die "annotated tag $sha could not be read" ;;
      *) die "tag v$GUARD_VERSION points at a $type, not a commit" ;;
    esac
  done
  die "tag v$GUARD_VERSION is nested too deeply"
}

cmd_manifest_binding() {
  need_version
  [ -f "${1:-}" ] || die "no manifest file: ${1:-}"
  node -e '
    const fs = require("fs");
    const fail = (m) => { console.error("publish-guard: " + m); process.exit(1); };
    let m;
    try { m = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { fail("the manifest is not JSON"); }
    if (!m || typeof m !== "object") fail("the manifest is not an object");
    if (m.id !== "glyphsift-release") fail("the manifest id is " + JSON.stringify(m.id) + ", not glyphsift-release");
    if (m.version !== process.argv[2]) fail("the manifest version is " + JSON.stringify(m.version) + ", not " + process.argv[2]);
    if (m.publisher !== "Airplane Mode Labs") fail("the manifest publisher is not the release publisher");
    if ("expiresAt" in m) fail("a release manifest carries no expiresAt (TD-121)");
    if (!Array.isArray(m.signatures) || m.signatures.length < 1) fail("the manifest carries no signature");
  ' "$(to_native "$1")" "$GUARD_VERSION"
}

lookup_404() { # <label> <url>: only an HTTP 404 means "this version is not on that registry"; anything else, including a failed request, is a refusal
  local code
  code=$(curl -sS -o /dev/null -w '%{http_code}' --proto '=https' --tlsv1.2 --max-time 30 -A 'airplanemode-release-guard' "$2") || die "$1: the lookup failed, so absence cannot be shown ($2)"
  [ "$code" = 404 ] || die "$1: expected 404 for this version, got $code ($2)"
  echo "ok: $1 answers 404 for $GUARD_VERSION"
}
cmd_registry_absent() {
  need_version
  lookup_404 "npm @airplanemode/glyphsift" "https://registry.npmjs.org/@airplanemode%2Fglyphsift/$GUARD_VERSION"
  lookup_404 "PyPI glyphsift" "https://pypi.org/pypi/glyphsift/$GUARD_VERSION/json"
  lookup_404 "crates.io glyphsift-core" "https://crates.io/api/v1/crates/glyphsift-core/$GUARD_VERSION"
  lookup_404 "crates.io glyphsift-cli" "https://crates.io/api/v1/crates/glyphsift-cli/$GUARD_VERSION"
}

cmd_exact_set() {
  need_version
  local dir=${1:-} out=${2:-} v=$GUARD_VERSION f n lin=0 mac=0 win=0
  [ -d "$dir" ] && [ ! -L "$dir" ] || die "$dir is not a real directory"
  [ -n "$out" ] || die "no output directory"
  mkdir -p "$out"
  local want_npm="airplanemode-glyphsift-$v.tgz" want_sdist="glyphsift-$v.tar.gz" want_core="glyphsift-core-$v.crate" want_cli="glyphsift-cli-$v.crate"
  local names=()
  while IFS= read -r n; do names+=("$n"); done < <(ls -A "$dir" | LC_ALL=C sort)
  : > "$out/npm.txt"; : > "$out/pypi.txt"; : > "$out/crates.txt"; : > "$out/all.txt"
  local seen_manifest=0 seen_sums=0 seen_npm=0 seen_sdist=0 seen_core=0 seen_cli=0
  for n in ${names[@]+"${names[@]}"}; do
    f=$dir/$n
    [ -f "$f" ] && [ ! -L "$f" ] || die "$n is not a regular file"
    case "$n" in
      release-manifest.json) seen_manifest=1; continue ;;
      SHA256SUMS) seen_sums=1; continue ;;
      "$want_npm") seen_npm=1; echo "$n" >> "$out/npm.txt" ;;
      "$want_sdist") seen_sdist=1; echo "$n" >> "$out/pypi.txt" ;;
      "$want_core") seen_core=1; echo "$n" >> "$out/crates.txt" ;;
      "$want_cli") seen_cli=1; echo "$n" >> "$out/crates.txt" ;;
      "glyphsift-$v-cp39-abi3-"manylinux*_x86_64*.whl) lin=$((lin+1)); echo "$n" >> "$out/pypi.txt" ;;
      "glyphsift-$v-cp39-abi3-macosx_"*_arm64.whl) mac=$((mac+1)); echo "$n" >> "$out/pypi.txt" ;;
      "glyphsift-$v-cp39-abi3-win_amd64.whl") win=$((win+1)); echo "$n" >> "$out/pypi.txt" ;;
      *) die "unexpected file in the verified set: $n" ;;
    esac
    echo "$n" >> "$out/all.txt"
  done
  [ "$seen_manifest" = 1 ] && [ "$seen_sums" = 1 ] || die "release-manifest.json or SHA256SUMS is missing"
  [ "$seen_npm" = 1 ] && [ "$seen_sdist" = 1 ] && [ "$seen_core" = 1 ] && [ "$seen_cli" = 1 ] || die "the tarball, the sdist or a crate is missing"
  [ "$lin" = 1 ] && [ "$mac" = 1 ] && [ "$win" = 1 ] || die "expected exactly one wheel each for manylinux x86_64, macOS arm64 and win_amd64 (got $lin, $mac, $win)"
  echo "ok: the verified set is exactly the expected $(wc -l < "$out/all.txt" | tr -d ' ') artefacts, the manifest and SHA256SUMS"
}

cmd_crate_digests() {
  need_version
  local dir=${1:-} pkg=${2:-}
  [ -f "$dir/release-manifest.json" ] || die "no release-manifest.json in $dir"
  [ -d "$pkg" ] || die "$pkg is not a directory"
  node -e '
    const fs = require("fs"), crypto = require("crypto"), path = require("path");
    const fail = (m) => { console.error("publish-guard: " + m); process.exit(1); };
    const [dir, pkg, v] = process.argv.slice(1);
    const m = JSON.parse(fs.readFileSync(path.join(dir, "release-manifest.json"), "utf8"));
    for (const name of ["glyphsift-core-" + v + ".crate", "glyphsift-cli-" + v + ".crate"]) {
      const e = (m.entries || []).find((x) => x.id === name);
      if (!e) fail(name + " is not in the verified manifest");
      let bytes;
      try { bytes = fs.readFileSync(path.join(pkg, name)); } catch (err) { fail(name + " was not re-packaged in " + pkg); }
      const sha = crypto.createHash("sha256").update(bytes).digest("hex");
      if (sha !== e.sha256) fail(name + ": the re-packaged crate has sha256 " + sha + ", the verified manifest says " + e.sha256);
      console.log("ok: " + name + " re-packaged to the verified digest");
    }
  ' "$(to_native "$dir")" "$(to_native "$pkg")" "$GUARD_VERSION"
}

# the sha256 the verified manifest lists for one entry id (64 lower-case hex, or a refusal)
manifest_sha() { # <dir> <entry id>
  node -e '
    const fs = require("fs"), path = require("path");
    const fail = (m) => { console.error("publish-guard: " + m); process.exit(1); };
    let m;
    try { m = JSON.parse(fs.readFileSync(path.join(process.argv[1], "release-manifest.json"), "utf8")); } catch (e) { fail("release-manifest.json is not JSON"); }
    const e = (m.entries || []).find((x) => x && x.id === process.argv[2]);
    if (!e) fail(process.argv[2] + " is not in the verified manifest");
    if (typeof e.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(e.sha256)) fail(process.argv[2] + ": the manifest digest is not 64 lower-case hex characters");
    process.stdout.write(e.sha256);
  ' "$(to_native "$1")" "$2"
}

# one look at one crate in crates.io's sparse index. Returns 0 when the line of this version carries the signed cksum, 10 when the answer may still change
# (not there yet, server trouble, no line for this version: the caller asks again), and exits 1 for anything that asking again cannot fix.
check_one_crate() { # <crate> <signed sha256>
  local crate=$1 want=$2 url tmp code rc
  url="https://index.crates.io/${crate:0:2}/${crate:2:2}/$crate"
  tmp=$(mktemp "${TMPDIR:-/tmp}/crate-index.XXXXXX")
  code=$(curl -sS -o "$tmp" -w '%{http_code}' --proto '=https' --tlsv1.2 --max-time 20 -A 'airplanemode-release-guard' -H 'Cache-Control: no-cache' "$url") || { rm -f "$tmp"; echo "  $crate: the index request failed, will ask again"; return 10; }
  case "$code" in
    200) ;;
    404) rm -f "$tmp"; echo "  $crate: not in the index yet (404)"; return 10 ;;
    *) rm -f "$tmp"; echo "  $crate: the index answered $code, will ask again"; return 10 ;;
  esac
  rc=0
  node -e '
    const fs = require("fs");
    const [file, crate, version, want] = process.argv.slice(1);
    const fail = (code, m) => { console.error("publish-guard: " + m); process.exit(code); };
    const lines = fs.readFileSync(file, "utf8").split("\n").filter((l) => l.trim() !== "");
    const hits = [];
    for (const l of lines) {
      let j;
      try { j = JSON.parse(l); } catch (e) { fail(13, crate + ": a line of the crates.io index is not JSON"); }
      if (!j || typeof j !== "object" || j.name !== crate || typeof j.vers !== "string") fail(13, crate + ": a line of the crates.io index is not an entry of this crate");
      if (j.vers === version) hits.push(j);
    }
    if (hits.length === 0) { console.log("  " + crate + ": the index has no line for " + version + " yet"); process.exit(10); }
    if (hits.length > 1) fail(14, crate + " " + version + ": the crates.io index has " + hits.length + " lines for this version");
    const h = hits[0];
    if (h.yanked === true) fail(12, crate + " " + version + " is yanked on crates.io");
    if (typeof h.cksum !== "string" || h.cksum !== want) fail(11, "STOP: crates.io holds " + crate + " " + version + " with cksum " + h.cksum + ", but the signed manifest says " + want + ": the uploaded bytes are not the signed bytes (the registry is immutable: yank the version, do not publish again)");
    console.log("ok: " + crate + " " + version + " is in the crates.io index with the signed cksum");
  ' "$(to_native "$tmp")" "$crate" "$GUARD_VERSION" "$want" || rc=$?
  rm -f "$tmp"
  if [ "$rc" -eq 0 ]; then return 0; fi
  if [ "$rc" -eq 10 ]; then return 10; fi
  exit 1
}

cmd_crate_index() { # <dir> [<window> [<interval>]]
  need_version
  local dir=${1:-} window=600 interval=15 core_sha cli_sha
  if [ "$#" -ge 2 ]; then window=$2; fi
  if [ "$#" -ge 3 ]; then interval=$3; fi
  [[ "$window" =~ ^[1-9][0-9]*$ ]] && [ "$window" -le 600 ] || die "the retry window must be a whole number of seconds from 1 to 600 (got '$window')"
  [[ "$interval" =~ ^[1-9][0-9]*$ ]] && [ "$interval" -le "$window" ] || die "the retry interval must be a whole number of seconds from 1 to the window (got '$interval')"
  [ -f "$dir/release-manifest.json" ] || die "no release-manifest.json in $dir"
  core_sha=$(manifest_sha "$dir" "glyphsift-core-$GUARD_VERSION.crate") || exit 1
  cli_sha=$(manifest_sha "$dir" "glyphsift-cli-$GUARD_VERSION.crate") || exit 1
  local start=$SECONDS n=0 max=$((window / interval)) done_core=0 done_cli=0 pending
  while :; do
    n=$((n+1))
    if [ "$done_core" = 0 ]; then check_one_crate glyphsift-core "$core_sha" && done_core=1 || { [ "$?" -eq 10 ] || exit 1; }; fi
    if [ "$done_cli" = 0 ]; then check_one_crate glyphsift-cli "$cli_sha" && done_cli=1 || { [ "$?" -eq 10 ] || exit 1; }; fi
    if [ "$done_core" = 1 ] && [ "$done_cli" = 1 ]; then echo "ok: both crates are in the crates.io index at $GUARD_VERSION with the signed cksums"; return 0; fi
    if [ "$n" -gt "$max" ] || [ $((SECONDS - start)) -ge "$window" ]; then
      pending=""
      if [ "$done_core" = 0 ]; then pending="glyphsift-core"; fi
      if [ "$done_cli" = 0 ]; then pending="${pending:+$pending and }glyphsift-cli"; fi
      die "after $window seconds crates.io's index does not show $pending at $GUARD_VERSION with the signed cksum (they may still be propagating or the publish failed): check https://crates.io/crates/glyphsift-core/$GUARD_VERSION by hand, and do not publish again"
    fi
    sleep "$interval"
  done
}

sub=${1:-}
[ "$#" -ge 1 ] && shift
case "$sub" in
  version) cmd_version ;;
  dist-tag) cmd_dist_tag "${1:-}" ;;
  armed) cmd_armed ;;
  key-id) cmd_key_id ;;
  tag-binding) cmd_tag_binding ;;
  manifest-binding) cmd_manifest_binding "${1:-}" ;;
  registry-absent) cmd_registry_absent ;;
  exact-set) cmd_exact_set "${1:-}" "${2:-}" ;;
  crate-digests) cmd_crate_digests "${1:-}" "${2:-}" ;;
  crate-index) cmd_crate_index "$@" ;;
  *) echo "usage: publish-guard.sh version|dist-tag|armed|key-id|tag-binding|manifest-binding|registry-absent|exact-set|crate-digests|crate-index" >&2; exit 2 ;;
esac
