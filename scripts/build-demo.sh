#!/usr/bin/env bash
# Assemble the static demo into demo/dist/ for GitHub Pages (https://airplanemode-labs.github.io/glyphsift/).
#   1. scripts/build-wasm.sh  -> dist/wasm/web/{glyphsift.js,glyphsift_bg.wasm}
#   2. copy demo/{index.html,app.js,styles.css,samples.js} and the two web-target files into demo/dist/
#   2b. copy LICENSE, and NOTICE (which ends with scripts/demo-notice-extra.txt) as NOTICE.txt, into demo/dist/
#   3. write demo/dist/build.json {id, sha, source, dirty}: id = first 16 hex of sha256(glyphsift.js ++ glyphsift_bg.wasm),
#      sha = $GITHUB_SHA when it is a full 40-hex commit id (source "ci"), otherwise this checkout's HEAD (source "local",
#      dirty true when the tree has uncommitted or untracked files), or "" when there is no git checkout; the page shows
#      "Built from main at <sha12>" or "Local build <sha12>[-dirty]"
# Before building it runs scripts/check-demo-sources.sh: no innerHTML, outerHTML or
# insertAdjacentHTML in demo/*.js, no inline script, style or event handler in demo/index.html.
# demo/dist/ is a build product and is git-ignored; nothing here is committed.
set -euo pipefail
cd "$(dirname "$0")/.."

# cargo-installed tools and Homebrew live off PATH in some shells.
[ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"
[ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"

scripts/check-demo-sources.sh
scripts/build-wasm.sh

WEB=dist/wasm/web
for f in glyphsift.js glyphsift_bg.wasm; do
  [ -f "$WEB/$f" ] || { echo "error: $WEB/$f missing after build-wasm.sh" >&2; exit 1; }
done

OUT=demo/dist
rm -rf "./$OUT"
mkdir -p "$OUT/pkg"
cp demo/index.html demo/app.js demo/styles.css demo/samples.js "$OUT/"
cp "$WEB/glyphsift.js" "$WEB/glyphsift_bg.wasm" "$OUT/pkg/"
# Notices for the compiled crates: LICENSE (Apache-2.0) covers every crate offered under Apache-2.0; NOTICE
# is written as NOTICE.txt (the root NOTICE already ends with the MIT texts of the two crates that are not Apache-2.0: memchr, zmij).
# The .txt extension matters: GitHub Pages serves a file with no extension as application/octet-stream, so
# a link to a bare NOTICE downloads it instead of showing it (BUG-T1-S3-R2-01). There is no bare NOTICE.
cp LICENSE "$OUT/LICENSE"
cp NOTICE "$OUT/NOTICE.txt"

sha256_of_stream() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else sha256sum | cut -d' ' -f1; fi
}
ID=$(cat "$OUT/pkg/glyphsift.js" "$OUT/pkg/glyphsift_bg.wasm" | sha256_of_stream | cut -c1-16)
# The build id the page shows (Sprint 5 convention): "Built from main at <sha12>" when CI built it (GITHUB_SHA is a
# full lowercase 40-hex commit id, anything else is ignored), otherwise "Local build <sha12>[-dirty]" from this
# checkout's own HEAD (dirty when anything is uncommitted or untracked), or "Local build" alone when there is no git
# checkout of this repository. Only this repository's own .git is asked (git -C <absolute path>, and only when that
# path is the top level of the work tree), so a copy of the sources inside some other repository never reports that
# repository's commit.
ROOT=$(pwd -P)
SHA=""; SOURCE=local; DIRTY=false
if [[ "${GITHUB_SHA:-}" =~ ^[0-9a-f]{40}$ ]]; then
  SHA=$GITHUB_SHA; SOURCE=ci
elif [ "$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)" = "$ROOT" ]; then
  HEAD_SHA=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)
  if [[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]]; then
    SHA=$HEAD_SHA
    if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then DIRTY=true; fi
  fi
fi
printf '{"id":"%s","sha":"%s","source":"%s","dirty":%s}\n' "$ID" "$SHA" "$SOURCE" "$DIRTY" > "$OUT/build.json"

echo "demo assembled in $OUT (module id $ID, source $SOURCE, sha ${SHA:-none}, dirty $DIRTY)"
find "$OUT" -type f | sort
