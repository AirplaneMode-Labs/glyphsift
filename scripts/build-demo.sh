#!/usr/bin/env bash
# Assemble the static demo into demo/dist/ for GitHub Pages (https://airplanemode-labs.github.io/glyphsift/).
#   1. scripts/build-wasm.sh  -> dist/wasm/web/{glyphsift.js,glyphsift_bg.wasm}
#   2. copy demo/{index.html,app.js,styles.css,samples.js} and the two web-target files into demo/dist/
#   3. write demo/dist/build.json {id, sha}: id = first 16 hex of sha256(glyphsift.js ++ glyphsift_bg.wasm),
#      sha = $GITHUB_SHA or "local"
# demo/dist/ is a build product and is git-ignored; nothing here is committed.
set -euo pipefail
cd "$(dirname "$0")/.."

# cargo-installed tools and Homebrew live off PATH in some shells.
[ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"
[ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"

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

sha256_of_stream() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else sha256sum | cut -d' ' -f1; fi
}
ID=$(cat "$OUT/pkg/glyphsift.js" "$OUT/pkg/glyphsift_bg.wasm" | sha256_of_stream | cut -c1-16)
SHA=${GITHUB_SHA:-local}
printf '{"id":"%s","sha":"%s"}\n' "$ID" "$SHA" > "$OUT/build.json"

echo "demo assembled in $OUT (module id $ID, sha $SHA)"
find "$OUT" -type f | sort
