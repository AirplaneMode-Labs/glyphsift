#!/usr/bin/env bash
# D3-01: the vendored release tool is byte for byte the spec's, every shared vector gives its verdict through it, and the old manifest script
# agrees with it (Sprint 7; TD-103, TD-104). Nothing here reads a sibling repository: the pins are in scripts/release/VENDORED.json.
#
#   tests/scripts/release-tool-vendored.sh
#
#  A. scripts/release/VENDORED.json names the source, spec release 0.6.1, the tool's sha256 and the vectors' listing sha256; the files on disk equal them.
#  B. git cannot change those bytes: the tool, the vectors and VENDORED.json are '-text' in .gitattributes (so core.autocrlf=true on a Windows checkout
#     leaves the digest alone), and none of them holds a carriage return.
#  C. every case of scripts/release/vectors/release.json gives its exit code, its reason and its first stderr line through the vendored tool
#     (tests/scripts/release-tool-cases.mjs; the junction case runs on Windows only and the CI rehearsal runs this harness there too).
#  D. parity: for the id glyphsift-release, `release-tool manifest` and scripts/release-manifest.mjs write the same bytes.
#  E. the tool's own rules, read from the bundle: its imports are the six allowed node: modules, there is no network, process or dynamic-code access, and exactly
#     one environment variable (SOURCE_DATE_EPOCH) is read, so the test-key flag cannot come from the environment (R3).
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1
TOOL=scripts/release/release-tool.mjs
PIN=scripts/release/VENDORED.json
VEC=scripts/release/vectors
command -v node >/dev/null || { fail "node not found: this test needs Node 22"; finish; exit 1; }
[ -f "$TOOL" ] && ok "$TOOL exists" || fail "$TOOL exists"
[ -f "$PIN" ] && ok "$PIN exists" || fail "$PIN exists"
[ -d "$VEC" ] && ok "$VEC exists" || fail "$VEC exists"
pinget() { node -e 'let j;try{j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))}catch{process.exit(3)};const v=j[process.argv[2]];process.stdout.write(v===undefined?"":String(v))' "$PIN" "$1" 2>/dev/null; }

echo "== A. the pins"
expect_eq "VENDORED.json: specRelease is 0.6.1" 0.6.1 "$(pinget specRelease)"
case "$(pinget source)" in *"AirplaneMode-Labs/runtime"*"spec/tools/release-tool.mjs"*) ok "VENDORED.json: source names AirplaneMode-Labs/runtime spec/tools/release-tool.mjs" ;; *) fail "VENDORED.json: source names AirplaneMode-Labs/runtime spec/tools/release-tool.mjs" ;; esac
TOOL_SHA=$(node -e 'process.stdout.write(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$TOOL" 2>/dev/null)
expect_eq "the tool's sha256 equals VENDORED.json" "$(pinget sha256)" "$TOOL_SHA"
expect_eq "the tool's sha256 is the one D1 landed (D1/LANDED.json, spec 0.6.1)" 81583057ea68b45890f8192e696418e59fb0faa8862a166dd37d3bd46b667387 "$TOOL_SHA"
VEC_SHA=$(node -e '
  const fs=require("fs"),c=require("crypto"),p=require("path");
  const root=process.argv[1], rows=[];
  (function walk(d){ for (const n of fs.readdirSync(d)) { const f=p.join(d,n); if (fs.statSync(f).isDirectory()) walk(f); else rows.push([ "vectors/release/" + p.relative(root,f).split(p.sep).join("/"), c.createHash("sha256").update(fs.readFileSync(f)).digest("hex") ]); } })(root);
  rows.sort((a,b)=> a[0]<b[0]?-1:1);
  process.stdout.write(c.createHash("sha256").update(rows.map(r=>r[1]+"  "+r[0]+"\n").join("")).digest("hex") + " " + rows.length);
' "$VEC" 2>/dev/null)
expect_eq "the vectors' sorted-listing sha256 equals VENDORED.json (vectorsSha256)" "$(pinget vectorsSha256)" "${VEC_SHA% *}"
expect_eq "the vectors are 31 files" 31 "${VEC_SHA#* }"

echo "== B. -text and LF"
for pat in "scripts/release/release-tool.mjs -text" "scripts/release/vectors/** -text" "scripts/release/VENDORED.json -text"; do
  if grep -qxF "$pat" .gitattributes; then ok ".gitattributes has '$pat'"; else fail ".gitattributes has '$pat'"; fi
done
if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  for f in "$TOOL" "$PIN" "$VEC/base/SHA256SUMS" "$VEC/base/release-manifest.json" "$VEC/release.json"; do
    expect_eq "git reports text: unset for $f" "$f: text: unset" "$(git -C "$REPO" check-attr text -- "$f" | sed 's/  */ /g')"
  done
else
  echo "na   - git check-attr: not applicable here (no git work tree around this copy); the .gitattributes lines above were checked"
fi
CR=$(printf '\r')
expect_eq "the tool holds no carriage return" 0 "$(grep -c "$CR" "$TOOL" | tr -d ' ')"
expect_eq "no vector file holds a carriage return" 0 "$(grep -rlF "$CR" "$VEC" | wc -l | tr -d ' ')"

echo "== C. every shared vector through the vendored tool"
OUT=$(node tests/scripts/release-tool-cases.mjs --tool "$TOOL" --vectors "$VEC" 2>&1); RC=$?
printf '%s\n' "$OUT" | grep -E '^(FAIL|na  )' | sed 's/^/    /'
expect_eq "release-tool-cases.mjs exits 0" 0 "$RC"
expect_eq "no case failed" 0 "$(printf '%s\n' "$OUT" | grep -c '^FAIL')"
NCASES=$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).length))' "$VEC/release.json" 2>/dev/null)
NOK=$(printf '%s\n' "$OUT" | grep -c '^ok  ')
NNA=$(printf '%s\n' "$OUT" | grep -c '^na  ')
expect_eq "every case ran or is a platform-only case (the junction case off Windows)" "$NCASES" "$((NOK + NNA))"
expect_eq "36 cases in release.json" 36 "$NCASES"

echo "== D. parity with scripts/release-manifest.mjs"
S=$(mktemp -d "${TMPDIR:-/tmp}/release-tool-vendored.XXXXXX"); S=$(cd "$S" && pwd -P)
cleanup() { case "$S" in /*/release-tool-vendored.??????) rm -rf "$S" ;; esac; }
trap cleanup EXIT
mkdir -p "$S/art" "$S/repo/scripts/lib" "$S/repo/dist"
cp scripts/release-manifest.mjs "$S/repo/scripts/"; cp scripts/lib/confine.mjs "$S/repo/scripts/lib/"; cp Cargo.toml "$S/repo/"
printf 'a tarball\n' > "$S/art/airplanemode-glyphsift-0.1.3.tgz"; printf 'a wheel\n' > "$S/art/glyphsift-0.1.3-cp39-abi3-macosx_11_0_arm64.whl"
printf 'an sdist\n' > "$S/art/glyphsift-0.1.3.tar.gz"; printf 'a crate\n' > "$S/art/glyphsift-core-0.1.3.crate"
VERSION=$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
( cd "$S/repo" && SOURCE_DATE_EPOCH=1795132800 node scripts/release-manifest.mjs --out dist/release-manifest.json ../art/airplanemode-glyphsift-0.1.3.tgz ../art/glyphsift-0.1.3-cp39-abi3-macosx_11_0_arm64.whl ../art/glyphsift-0.1.3.tar.gz ../art/glyphsift-core-0.1.3.crate ) > /dev/null 2>&1
SOURCE_DATE_EPOCH=1795132800 node "$TOOL" manifest --dir "$S/art" --id glyphsift-release --version "$VERSION" --licence Apache-2.0 --publisher release > /dev/null 2>&1
if cmp -s "$S/art/release-manifest.json" "$S/repo/dist/release-manifest.json"; then ok "release-tool manifest and scripts/release-manifest.mjs write byte-identical output for glyphsift-release"; else fail "release-tool manifest and scripts/release-manifest.mjs write byte-identical output for glyphsift-release"; fi

echo "== E. the bundle's own limits"
node - "$TOOL" <<'JS'
const fs = require("fs");
const t = fs.readFileSync(process.argv[2], "utf8");
let bad = 0;
const check = (ok, what) => { console.log((ok ? "ok   - " : "FAIL - ") + what); if (!ok) bad += 1; };
const imports = [...t.matchAll(/(?:^|\n)\s*import\b[^;]*?from\s+["']([^"']+)["']/g)].map((m) => m[1]);
const allowed = new Set(["node:crypto", "node:fs", "node:fs/promises", "node:path", "node:process", "node:url"]);
check(imports.length > 0 && imports.every((i) => allowed.has(i)), `every import is one of the six allowed node: modules (${[...new Set(imports)].join(", ")})`);
for (const bad_ of ["node:http", "node:https", "node:net", "node:tls", "node:dns", "node:dgram", "node:child_process", "node:worker_threads", "node:vm", "node:module"]) check(!t.includes(bad_), `the bundle does not mention ${bad_}`);
for (const bad_ of ["fetch(", "WebSocket", "eval(", "new Function", "require("]) check(!t.includes(bad_), `the bundle does not contain ${JSON.stringify(bad_)}`);
check(!/[^.\w]import\(/.test(t), "the bundle has no dynamic import()");
const envReads = t.match(/process\.env/g) || [];
check(envReads.length === 1, `exactly one process.env read (${envReads.length})`);
check(/process\.env\.SOURCE_DATE_EPOCH|process\.env\[["']SOURCE_DATE_EPOCH["']\]/.test(t), "that read is SOURCE_DATE_EPOCH");
process.exit(bad ? 1 : 0);
JS
expect_eq "the bundle checks above all passed" 0 "$?"

finish
