#!/usr/bin/env bash
# D3-02: scripts/release/rehearse.sh, the release rehearsal, behaves as the release rules say, and its refusal proofs cannot pass by accident
# (Sprint 7; TD-103, TD-106; security conditions: exact refusal proofs and a self-test for each). It needs the vendored release tool and nothing else:
# no build, no network, no registry, no key. The three-operating-system run, with the real artefacts, is the CI job release-rehearsal; this test uses the
# script's `proofs` and `assert-dir` commands over small synthetic artefacts.
#
#   tests/scripts/rehearse.sh
#
#  A. proofs over synthetic artefacts: the manifest, SHA256SUMS (LF only, one line per artefact) and the test-key signature are written, the verification with
#     the flag succeeds and the six refusal proofs hold; two runs with the same SOURCE_DATE_EPOCH give byte-identical SHA256SUMS and release-manifest.json,
#     whatever GITHUB_SHA and GITHUB_REF say.
#  B. self-test, a missing tool: pointing the script at a tool that does not exist fails the rehearsal (it never counts as a refusal).
#  C. self-test, a tool that misbehaves: a verifier that crashes where a refusal is expected (exit 1), that exits 3 with another reason, that prints another
#     first stderr line, that accepts the test key without the flag, or that signs a release id, turns the rehearsal red.
#  D. assert-dir: a credential-looking name, a link, a subdirectory, a CRLF SHA256SUMS, a file the manifest does not list and a changed artefact are refused.
#  E. the script refuses unsafe paths and unknown commands.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1
command -v node >/dev/null || { fail "node not found: Node 22 is required"; finish; exit 1; }
REH=scripts/release/rehearse.sh
[ -f "$REH" ] || { fail "$REH exists"; finish; exit 1; }
[ -f scripts/release/release-tool.mjs ] || { fail "the vendored release tool exists"; finish; exit 1; }
S=$(mktemp -d "${TMPDIR:-/tmp}/rehearse-test.XXXXXX"); S=$(cd "$S" && pwd -P)
cleanup() { case "$S" in /*/rehearse-test.??????) rm -rf "$S" ;; esac; }
trap cleanup EXIT
EPOCH=1795132800
VERSION=$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)

mkart() { # <dir>: a release directory with four small synthetic artefacts named like the real ones
  rm -rf "$1"; mkdir -p "$1"
  printf 'synthetic tarball\n' > "$1/airplanemode-glyphsift-$VERSION.tgz"
  printf 'synthetic wheel\n' > "$1/glyphsift-$VERSION-cp39-abi3-macosx_11_0_arm64.whl"
  printf 'synthetic core crate\n' > "$1/glyphsift-core-$VERSION.crate"
  printf 'synthetic cli crate\n' > "$1/glyphsift-cli-$VERSION.crate"
}
# reh <name> <expected exit> [env assignments...] -- <args>: run the script in the repository with scratch directories; output in $S/<name>.log
reh() {
  local name=$1 want=$2; shift 2
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  [ "${1:-}" = -- ] && shift
  env -u GITHUB_SHA -u GITHUB_REF -u CI ${envs[@]+"${envs[@]}"} \
    RELEASE_DIR="$S/$name/dist-release" RELEASE_REPORT_DIR="$S/$name/dist-release-report" REHEARSE_ROOT="$S/$name/root" SOURCE_DATE_EPOCH=$EPOCH \
    bash "$REH" "$@" > "$S/$name.log" 2>&1
  RC=$?
  if [ "$RC" = "$want" ]; then ok "$name: exit $RC"; else fail "$name: exit $RC, expected $want ($(tail -2 "$S/$name.log" | tr '\n' ' ' | cut -c1-200))"; fi
}

echo "== A. proofs over synthetic artefacts"
mkdir -p "$S/a1"; mkart "$S/a1/dist-release"; reh a1 0 -- proofs
D=$S/a1/dist-release
for f in release-manifest.json SHA256SUMS; do [ -f "$D/$f" ] && ok "a1: $f was written" || fail "a1: $f was written"; done
expect_eq "a1: SHA256SUMS has one line per artefact (4)" 4 "$(wc -l < "$D/SHA256SUMS" | tr -d ' ')"
expect_eq "a1: SHA256SUMS holds no carriage return" 0 "$(grep -c "$(printf '\r')" "$D/SHA256SUMS" | tr -d ' ')"
expect_eq "a1: the manifest id is glyphsift-rehearsal" glyphsift-rehearsal "$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).id)' "$D/release-manifest.json")"
expect_eq "a1: the manifest has one signature (the test key) and no expiresAt" "1 false" "$(node -e 'const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(m.signatures.length+" "+("expiresAt" in m))' "$D/release-manifest.json")"
expect_eq "a1: the manifest's createdAt is SOURCE_DATE_EPOCH" 2026-11-20T00:00:00Z "$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).createdAt)' "$D/release-manifest.json")"
expect_eq "a1: six refusal proofs are in the report" 1 "$(grep -c 'ok: six refusal proofs' "$S/a1/dist-release-report/rehearsal-report.txt")"
for r in test_key_refused no_trusted_key expect_id_required test_key_flag_misuse test_key_release_id artifact_hash_mismatch; do
  expect_eq "a1: the report names the exact refusal $r" 1 "$(grep -c "ok: .*'$r\|ok: usage error 'usage: $r:'" "$S/a1/dist-release-report/rehearsal-report.txt" | awk '{print ($1 >= 1) ? 1 : 0}')"
done
expect_eq "a1: the report says the tool equals the pin" 1 "$(grep -c 'equals scripts/release/VENDORED.json' "$S/a1/dist-release-report/rehearsal-report.txt")"
expect_eq "a1: no real key or seed is anywhere in the report directory" 0 "$(grep -rlE '9d61b19d|pkcs8|PRIVATE KEY' "$S/a1/dist-release-report" | wc -l | tr -d ' ')"
mkdir -p "$S/a2"; mkart "$S/a2/dist-release"; reh a2 0 GITHUB_SHA=0123456789abcdef0123456789abcdef01234567 GITHUB_REF=refs/heads/other -- proofs
cmp -s "$S/a1/dist-release/SHA256SUMS" "$S/a2/dist-release/SHA256SUMS" && ok "two runs give byte-identical SHA256SUMS (GITHUB_SHA and GITHUB_REF set in the second)" || fail "two runs give byte-identical SHA256SUMS"
cmp -s "$S/a1/dist-release/release-manifest.json" "$S/a2/dist-release/release-manifest.json" && ok "two runs give byte-identical release-manifest.json" || fail "two runs give byte-identical release-manifest.json"
# a rerun over the same directory starts from the artefacts only
rm -rf "$S/a1/root"
reh a1 0 -- proofs
cmp -s "$S/a1/dist-release/SHA256SUMS" "$S/a2/dist-release/SHA256SUMS" && ok "a rerun over the same directory gives the same SHA256SUMS" || fail "a rerun over the same directory gives the same SHA256SUMS"
# a CRLF SHA256SUMS is refused by the verifier the rehearsal uses (sums_mismatch), which is why the file is -text wherever it is committed
node -e 'const fs=require("fs");const f=process.argv[1];fs.writeFileSync(f,fs.readFileSync(f,"utf8").replace(/\n/g,"\r\n"))' "$S/a2/dist-release/SHA256SUMS"
node scripts/release/release-tool.mjs verify --dir "$S/a2/dist-release" --expect-id glyphsift-rehearsal --trust-test-key --allow-test-key > /dev/null 2> "$S/crlf.err"; CRC=$?
expect_eq "SHA256SUMS converted to CRLF is refused: exit 3" 3 "$CRC"
expect_eq "SHA256SUMS converted to CRLF is refused: refused: sums_mismatch" "refused: sums_mismatch" "$(head -1 "$S/crlf.err" | tr -d '\r')"

echo "== B. self-test: a missing tool"
mkdir -p "$S/b1"; mkart "$S/b1/dist-release"; reh b1 1 RELEASE_TOOL="$S/no/such/release-tool.mjs" -- proofs
expect_eq "b1: the failure says the tool was not found" 1 "$(grep -c 'release tool not found' "$S/b1.log")"
mkdir -p "$S/b2"; mkart "$S/b2/dist-release"; cp scripts/release/release-tool.mjs "$S/b2/tool.mjs"; printf '\n// changed\n' >> "$S/b2/tool.mjs"
# the pin check runs for the default tool only; any other tool needs RELEASE_TOOL and the report says the pin check was skipped
expect_eq "b2: a tool other than the vendored one is only usable through RELEASE_TOOL (the pin check is skipped and said so)" 1 "$( env RELEASE_TOOL="$S/b2/tool.mjs" RELEASE_DIR="$S/b2/dist-release" RELEASE_REPORT_DIR="$S/b2/dist-release-report" REHEARSE_ROOT="$S/b2/root" SOURCE_DATE_EPOCH=$EPOCH bash "$REH" proofs 2>&1 | grep -c 'the VENDORED.json pin check is skipped (self-test only)')"

echo "== C. self-test: a tool that misbehaves turns the rehearsal red"
# the fake wraps the real tool and misbehaves on one command line, chosen by FAKE_MODE
cat > "$S/fake.mjs" <<'JS'
import { spawnSync } from "node:child_process";
const real = process.env.REAL_TOOL;
const args = process.argv.slice(2);
const mode = process.env.FAKE_MODE;
const noFlag = args[0] === "verify" && args.includes("--trust-test-key") && !args.includes("--allow-test-key") && args.includes("glyphsift-rehearsal");
const signRelease = args[0] === "sign";
const trustFile = args[0] === "verify" && args.includes("--trust-file");
const r = spawnSync(process.execPath, [real, ...args], { encoding: "utf8" });
const out = (code, stdout, stderr) => { process.stdout.write(stdout); process.stderr.write(stderr); process.exit(code); };
if (mode === "crash-on-refusal" && noFlag) out(1, "", "error: boom\n");
if (mode === "wrong-reason" && noFlag) out(3, '{"verdict":"refused","reason":"no_valid_signature"}\n', "refused: no_valid_signature\n");
if (mode === "wrong-first-line" && noFlag) out(3, '{"verdict":"refused","reason":"test_key_refused"}\n', "note: something first\nrefused: test_key_refused\n");
if (mode === "accepts-test-key" && noFlag) out(0, '{"verdict":"ok","id":"glyphsift-rehearsal","version":"x","entries":4,"testKey":true}\n', "");
if (mode === "stdout-mismatch" && noFlag) out(3, '{"verdict":"refused","reason":"other"}\n', "refused: test_key_refused\n");
if (mode === "release-id-signed" && signRelease && args.includes("--dir") && /release-id-probe/.test(args.join(" "))) out(0, "{}\n", "");
if (mode === "keys-accepted" && trustFile) out(0, '{"verdict":"ok","id":"glyphsift-rehearsal","version":"x","entries":4,"testKey":false}\n', "");
process.stdout.write(r.stdout ?? ""); process.stderr.write(r.stderr ?? ""); process.exit(r.status ?? 1);
JS
for mode in crash-on-refusal wrong-reason wrong-first-line accepts-test-key stdout-mismatch release-id-signed keys-accepted; do
  mkdir -p "$S/c-$mode"; mkart "$S/c-$mode/dist-release"
  reh "c-$mode" 1 RELEASE_TOOL="$S/fake.mjs" REAL_TOOL="$REPO/scripts/release/release-tool.mjs" FAKE_MODE="$mode" -- proofs
done
mkdir -p "$S/c-ok"; mkart "$S/c-ok/dist-release"; reh c-ok 0 RELEASE_TOOL="$S/fake.mjs" REAL_TOOL="$REPO/scripts/release/release-tool.mjs" FAKE_MODE=none -- proofs
expect_eq "c-crash-on-refusal: the message says an I/O error, a crash or a signal is not a refusal" 1 "$(grep -c 'is not a refusal' "$S/c-crash-on-refusal.log" | awk '{print ($1 >= 1) ? 1 : 0}')"

echo "== D. assert-dir"
ad() { # <name> <want> : run assert-dir over $S/<name>/dist-release
  env -u GITHUB_SHA bash "$REH" assert-dir "$S/$1/dist-release" > "$S/$1.log" 2>&1; RC=$?
  if [ "$RC" = "$2" ]; then ok "$1: exit $RC"; else fail "$1: exit $RC, expected $2 ($(tail -2 "$S/$1.log" | tr '\n' ' ' | cut -c1-160))"; fi
}
ad a1 0
fresh() { rm -rf "$S/$1"; mkdir -p "$S/$1"; cp -R "$S/a1/dist-release" "$S/$1/dist-release"; }
fresh d-npmrc; printf '//registry:_authToken=x\n' > "$S/d-npmrc/dist-release/.npmrc"; ad d-npmrc 1
for n in key.pem id.key sign.der k.pkcs8 my-seed.txt SEED.bin .pypirc; do fresh "d-$n"; printf 'x' > "$S/d-$n/dist-release/$n"; ad "d-$n" 1; done
fresh d-extra; printf 'x' > "$S/d-extra/dist-release/notes.txt"; ad d-extra 1
fresh d-subdir; mkdir "$S/d-subdir/dist-release/sub"; ad d-subdir 1
fresh d-link; ln -s "$S/a1/dist-release/SHA256SUMS" "$S/d-link/dist-release/link.txt"; ad d-link 1
fresh d-crlf; node -e 'const fs=require("fs");const f=process.argv[1];fs.writeFileSync(f,fs.readFileSync(f,"utf8").replace(/\n/g,"\r\n"))' "$S/d-crlf/dist-release/SHA256SUMS"; ad d-crlf 1
fresh d-changed; printf 'changed' >> "$S/d-changed/dist-release/glyphsift-core-$VERSION.crate"; ad d-changed 1
fresh d-missing; rm "$S/d-missing/dist-release/glyphsift-cli-$VERSION.crate"; ad d-missing 1
fresh d-nomanifest; rm "$S/d-nomanifest/dist-release/release-manifest.json"; ad d-nomanifest 1
ln -s "$S/a1/dist-release" "$S/dirlink"; env bash "$REH" assert-dir "$S/dirlink" > /dev/null 2>&1; expect_eq "a linked release directory is refused" 1 "$?"
env bash "$REH" assert-dir "$S/does-not-exist" > /dev/null 2>&1; expect_eq "a missing release directory is refused" 1 "$?"

echo "== E. unsafe paths and unknown commands"
env RELEASE_DIR="$S/e1/dist-release" bash "$REH" bogus > /dev/null 2>&1; expect_eq "an unknown command is a usage error (exit 2)" 2 "$?"
env bash "$REH" assert-dir > /dev/null 2>&1; expect_eq "assert-dir without a directory is a usage error (exit 2)" 2 "$?"
mkdir -p "$S/e2"; mkart "$S/e2/dist-release"
env RELEASE_DIR="../dist-release" RELEASE_REPORT_DIR="$S/e2/dist-release-report" SOURCE_DATE_EPOCH=$EPOCH bash "$REH" proofs > /dev/null 2>&1; expect_eq "RELEASE_DIR with a '..' segment is refused" 1 "$?"
env RELEASE_DIR="$S/e2/artefacts" RELEASE_REPORT_DIR="$S/e2/dist-release-report" SOURCE_DATE_EPOCH=$EPOCH bash "$REH" proofs > /dev/null 2>&1; expect_eq "a RELEASE_DIR that does not end in dist-release is refused (only that name is ever emptied)" 1 "$?"
env RELEASE_DIR="$S/e2/dist-release" RELEASE_REPORT_DIR="$S/e2/dist-release/dist-release-report" SOURCE_DATE_EPOCH=$EPOCH bash "$REH" proofs > /dev/null 2>&1; expect_eq "a report directory inside the release directory is refused" 1 "$?"
env RELEASE_DIR="$S/e2/dist-release" RELEASE_REPORT_DIR="$S/e2/dist-release-report" SOURCE_DATE_EPOCH=abc bash "$REH" proofs > /dev/null 2>&1; expect_eq "a non-numeric SOURCE_DATE_EPOCH is refused" 1 "$?"
env RELEASE_DIR="$S/e2/dist-release" RELEASE_REPORT_DIR="$S/e2/dist-release-report" REHEARSE_ROOT="$REPO/rehearse-root-inside-checkout" SOURCE_DATE_EPOCH=$EPOCH bash "$REH" proofs > /dev/null 2>&1; RCX=$?
expect_eq "a scratch root inside the checkout is refused" 1 "$RCX"
[ -e "$REPO/rehearse-root-inside-checkout" ] && { fail "no scratch root was created inside the checkout"; rmdir "$REPO/rehearse-root-inside-checkout" 2>/dev/null; } || ok "no scratch root was created inside the checkout"

finish
