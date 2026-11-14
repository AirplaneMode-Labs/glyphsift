#!/usr/bin/env bash
# Tests for scripts/release-manifest.mjs: an unsigned airplanemode.manifest/0.1 for the release
# artifacts (the wheel and the npm tarball). Runs against a scratch copy of the layout (scripts/,
# Cargo.toml, dist/), so the real tree is untouched. Written before the script (red-D3-09.log).
#
# The script is the same contract as pagetriage's scripts/release-manifest.mjs; only the constants at
# its top differ (id, licence), and these tests check exactly those two.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

command -v node >/dev/null || { echo "SKIP - node not found"; exit 0; }
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/scripts" "$SCRATCH/dist" "$SCRATCH/art" "$SCRATCH/outside"
cp "$SCRIPTS_DIR/release-manifest.mjs" "$SCRATCH/scripts/" 2>/dev/null
cp "$REPO/Cargo.toml" "$SCRATCH/Cargo.toml"
VERSION=$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' "$REPO/Cargo.toml" | head -1)
printf 'wheel bytes\n' > "$SCRATCH/art/Glyphsift-0.1.0-cp39-abi3-macosx_11_0_arm64.whl"
head -c 4096 /dev/zero | tr '\0' 'x' > "$SCRATCH/art/airplanemode-glyphsift-0.1.0.tgz"
printf 'x' > "$SCRATCH/art/a b.tgz"
sha() { if command -v shasum >/dev/null; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
rm_run() { ( cd "$SCRATCH" && env "$@" >/dev/null 2>&1; echo $? ); }
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

expect_eq "'../x' out refused" 2 "$(rm_run $RM --out ../x.json $T)"
expect_eq "'dist/../x' out refused" 2 "$(rm_run $RM --out dist/../x.json $T)"
expect_eq "out outside dist/ refused" 2 "$(rm_run $RM --out out.json $T)"
expect_eq "absolute out outside dist/ refused" 2 "$(rm_run $RM --out "$SCRATCH/outside/x.json" $T)"
expect_eq "absolute out inside dist/ accepted" 0 "$(rm_run $RM --out "$SCRATCH/dist/abs.json" $T)"
expect_eq "nested new dir inside dist/ accepted" 0 "$(rm_run $RM --out dist/sub/dir/n.json $T)"
if ln -s "$SCRATCH/outside" "$SCRATCH/dist/link" 2>/dev/null; then
  expect_eq "--out through a symlink leaving dist/ refused" 2 "$(rm_run $RM --out dist/link/x.json $T)"
  expect_eq "nothing written through the symlink" no "$([ -e "$SCRATCH/outside/x.json" ] && echo yes || echo no)"
  ln -s "$SCRATCH/outside/target.json" "$SCRATCH/dist/filelink.json"
  expect_eq "--out that is itself a symlink leaving dist/ refused" 2 "$(rm_run $RM --out dist/filelink.json $T)"
  expect_eq "nothing written through the file symlink" no "$([ -e "$SCRATCH/outside/target.json" ] && echo yes || echo no)"
else
  echo "skip - cannot create symlinks here"
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
expect_eq "script has no key or sign option" 0 "$(grep -Ec -- '--(key|sign|secret|seed|priv)|\.secret|\.pem|createPrivateKey|sign\(' "$SCRIPTS_DIR/release-manifest.mjs" 2>/dev/null | head -1)"
expect_eq "script has no dependencies" 0 "$(grep -E "^import|require\(" "$SCRIPTS_DIR/release-manifest.mjs" 2>/dev/null | grep -vc "node:")"

# The glyphsift copy differs from pagetriage's in its constants only: id and licence (both pinned here).
expect_eq "constants: manifest id is glyphsift-release" 1 "$(grep -c '^const MANIFEST_ID = "glyphsift-release";' "$SCRIPTS_DIR/release-manifest.mjs" 2>/dev/null)"
expect_eq "constants: licence is Apache-2.0" 1 "$(grep -c '^const LICENCE = "Apache-2.0";' "$SCRIPTS_DIR/release-manifest.mjs" 2>/dev/null)"
expect_eq "constants: version comes from Cargo.toml" 1 "$(grep -c '^const VERSION_SOURCE = "Cargo.toml";' "$SCRIPTS_DIR/release-manifest.mjs" 2>/dev/null)"
finish
