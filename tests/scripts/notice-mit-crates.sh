#!/usr/bin/env bash
# BUG-T3-S4-18: every crate in the glyphsift-cli, py, wasm and core normal trees whose cargo-metadata licence is
# exactly "MIT" (and memchr, taken under MIT) has a "----- <name> <version>" block in NOTICE with the full MIT
# text, the four crate NOTICE copies equal the root NOTICE, and the sentence naming the non-Apache crates is complete.
set -uo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
cd "$REPO"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
META=$(mktemp); trap 'rm -f "$META"' EXIT
cargo metadata --locked --format-version 1 >"$META" || { echo "cargo metadata failed"; exit 1; }
LIST=$(for p in glyphsift-cli glyphsift-py glyphsift-wasm glyphsift-core; do
  cargo tree --locked -p "$p" -e normal --prefix none --target all 2>/dev/null | sed -E 's/ \(.*//; s/ v/ /' ; done | sort -u)
MITONLY=$(node -e '
const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
const want=new Set(require("fs").readFileSync(0,"utf8").split("\n").filter(Boolean));
const out=[];
for(const p of m.packages){ if(!want.has(p.name+" "+p.version)) continue;
  if(p.license==="MIT"||p.name==="memchr") out.push(p.name+" "+p.version); }
console.log(out.sort().join("\n"));' "$META" <<<"$LIST")
[ -n "$MITONLY" ] || { bad "no MIT-only crates found (tree parse failed)"; exit 1; }
while read -r nv; do
  if grep -Eq -- "^----- ${nv%% *}( |\$)" NOTICE; then ok "NOTICE has a block for $nv"; else bad "NOTICE has no block for $nv"; fi
done <<<"$MITONLY"
n=$(grep -c "^Permission is hereby granted" NOTICE)
want=$(grep -c . <<<"$MITONLY")
[ "$n" -ge "$want" ] && ok "NOTICE has $n MIT texts for $want crates" || bad "NOTICE has $n MIT texts for $want crates"
names=$(awk '{print $1}' <<<"$MITONLY" | sort -u)
sentence=$(grep -n "not offered under Apache-2.0" NOTICE | head -1)
for c in $names; do grep -A1 "not offered under Apache-2.0" NOTICE | grep -q "$c" && ok "line-14 sentence names $c" || bad "line-14 sentence omits $c"; done
for f in crates/*/NOTICE; do cmp -s NOTICE "$f" && ok "$f equals NOTICE" || bad "$f differs from NOTICE"; done
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
