#!/usr/bin/env bash
# Install the pinned WASM toolchain from official release binaries, verifying each tarball against a
# SHA-256 digest pinned in this script (never against a checksum file fetched from the same release,
# which would only detect transit corruption):
#   - wasm-bindgen CLI, at the exact version pinned in crates/glyphsift-wasm/Cargo.toml
#   - binaryen (wasm-opt), at BINARYEN_VERSION
# Bumping either version means adding the new tarballs' digests to expected_digest below.
# Used by CI; also fine locally. Installs under $INSTALL_ROOT (default ~/.local/glyphsift-tools)
# and, when run in GitHub Actions, adds the bin directories to PATH for later steps. Otherwise it
# prints the PATH line to use.
# wasm-opt links against ../lib/libbinaryen, so the whole binaryen tree is kept, not just the binary.
set -euo pipefail
cd "$(dirname "$0")/.."

WBG_VERSION=$(sed -n 's/^wasm-bindgen = "=\(.*\)"/\1/p' crates/glyphsift-wasm/Cargo.toml)
BINARYEN_VERSION=${BINARYEN_VERSION:-133}
ROOT=${INSTALL_ROOT:-$HOME/.local/glyphsift-tools}

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  WBG_TARGET=x86_64-unknown-linux-musl; BIN_TARGET=x86_64-linux ;;
  Darwin-arm64)  WBG_TARGET=aarch64-apple-darwin;      BIN_TARGET=arm64-macos ;;
  Darwin-x86_64) WBG_TARGET=x86_64-apple-darwin;       BIN_TARGET=x86_64-macos ;;
  *) echo "error: unsupported platform $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# download <url> <name>: release tarballs only, from the two GitHub release hosts below.
download() { curl -fsSL --retry 3 --proto '=https' --tlsv1.2 -o "$TMP/$2" "$1"; }

# expected_digest <asset-name>: the SHA-256 of that release tarball, pinned here (recorded 2026-11-09
# from the published release files). An asset without a row is an error: add its digest, do not
# fall back to a checksum file.
expected_digest() {
  case "$1" in
    wasm-bindgen-0.2.129-x86_64-unknown-linux-musl) echo 82d12bb940e2d4e72e0d5605387fc1b8ca179044e012b620f0ce4e7440e8320e ;;
    wasm-bindgen-0.2.129-aarch64-apple-darwin)      echo 81d4a23d56b3c3eb8187658329116d50e0b228a93b343825fb71f70179051cd1 ;;
    wasm-bindgen-0.2.129-x86_64-apple-darwin)       echo 7e028879a68ec53dae14048b55cc5215f6df75b17a9c1426fac8fa086d3202fd ;;
    binaryen-version_133-x86_64-linux)              echo 2dc9c7813f5375db93d96ead4b78222fcc3e2677bbb832297af4797782a37489 ;;
    binaryen-version_133-arm64-macos)               echo ad66da82ac13f163e424b1643f16c6dfcccc98b5966296b43e52d3cab04f84a8 ;;
    binaryen-version_133-x86_64-macos)              echo 13a9b90be775c6389ce3d1f879cb8627bea56708ba8c122983941d53a8199b95 ;;
    *) echo "error: no pinned SHA-256 for $1 (new version or platform): add it to expected_digest in $0" >&2; return 1 ;;
  esac
}

# sha256_of <file>: shasum (perl, present on macOS and the GitHub runners), else openssl.
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; else openssl dgst -sha256 "$1" | awk '{print $NF}'; fi
}

# check <tarball> <asset-name>: compare the download with the pinned digest; both are printed on a mismatch.
check() {
  local want got
  want=$(expected_digest "$2") || exit 1
  got=$(sha256_of "$1")
  if [ "$want" != "$got" ]; then
    echo "error: SHA-256 mismatch for $2: pinned $want, downloaded $got" >&2
    exit 1
  fi
  echo "verified $2 ($got)"
}

mkdir -p "$ROOT"

WBG_NAME="wasm-bindgen-${WBG_VERSION}-${WBG_TARGET}"
WBG_URL="https://github.com/wasm-bindgen/wasm-bindgen/releases/download/${WBG_VERSION}/${WBG_NAME}.tar.gz"
download "$WBG_URL" wbg.tar.gz
check "$TMP/wbg.tar.gz" "$WBG_NAME"
rm -rf "$ROOT/wasm-bindgen"; mkdir -p "$ROOT/wasm-bindgen"
tar -xzf "$TMP/wbg.tar.gz" -C "$ROOT/wasm-bindgen" --strip-components=1

BIN_NAME="binaryen-version_${BINARYEN_VERSION}-${BIN_TARGET}"
BIN_URL="https://github.com/WebAssembly/binaryen/releases/download/version_${BINARYEN_VERSION}/${BIN_NAME}.tar.gz"
download "$BIN_URL" bin.tar.gz
check "$TMP/bin.tar.gz" "$BIN_NAME"
rm -rf "$ROOT/binaryen"; mkdir -p "$ROOT/binaryen"
tar -xzf "$TMP/bin.tar.gz" -C "$ROOT/binaryen" --strip-components=1

echo "installed wasm-bindgen ${WBG_VERSION} and binaryen ${BINARYEN_VERSION} under $ROOT"
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$ROOT/wasm-bindgen" >> "$GITHUB_PATH"
  echo "$ROOT/binaryen/bin" >> "$GITHUB_PATH"
else
  echo "add to PATH:  export PATH=\"$ROOT/wasm-bindgen:$ROOT/binaryen/bin:\$PATH\""
fi
