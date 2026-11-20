#!/usr/bin/env bash
# Install the glyphsift CLI from the PACKAGED crate files, with no registry in the way (Sprint 7, D3-02, TD-106 and S1's rule that no
# '-core' crate is ever resolved from crates.io by a team job).
#
#   scripts/release/install-crate-offline.sh <glyphsift-core-X.crate> <glyphsift-cli-X.crate> <work dir> <install root>
#
# <work dir> and <install root> must not exist or must be empty. What it does, in order:
#   1. unpacks the CLI .crate (the source `cargo install` will build);
#   2. makes a cargo DIRECTORY SOURCE: `cargo vendor --locked` from this checkout writes the third-party crates (the only step that may use
#      the network; the packaged crate's own dependencies are not fetched from anywhere else), and the packaged glyphsift-core .crate is unpacked
#      into the same directory with a .cargo-checksum.json whose "package" hash is the .crate file's own sha256 (scripts/release/dirsource-checksum.mjs);
#   3. writes a cargo config file that replaces crates-io with that directory and sets net.offline, passed with --config (no ~/.cargo/config is read or written);
#   4. runs `cargo install --path <unpacked cli> --offline --locked --root <install root>` and reads the log (colour and CR stripped): it must say
#      `Compiling glyphsift-core v<version>` and `Installed package`, and must contain no `Downloading`, `Downloaded` or `Updating` line, which is the
#      proof that glyphsift-core came from the packaged file and not from a registry.
# The installed binary is <install root>/bin/glyphsift (glyphsift.exe on Windows). Exit 0 on success, 1 on any failed check, 2 on a usage error.
set -euo pipefail
cd "$(dirname "$0")/../.."

die() { echo "install-crate-offline: $*" >&2; exit 1; }
usage() { echo "usage: scripts/release/install-crate-offline.sh <glyphsift-core-X.crate> <glyphsift-cli-X.crate> <work dir> <install root>" >&2; exit 2; }
[ "$#" -eq 4 ] || usage
CORE=$1; CLI=$2; WORK=$3; ROOT=$4
to_native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
strip_ansi() { local esc cr; esc=$(printf '\033'); cr=$(printf '\r'); LC_ALL=C sed -e "s/${esc}\\[[0-9;]*[A-Za-z]//g" -e "s/${cr}\$//"; }
[ -f "$CORE" ] && [ ! -L "$CORE" ] || die "not a regular file: $CORE"
[ -f "$CLI" ] && [ ! -L "$CLI" ] || die "not a regular file: $CLI"
CORE_BASE=$(basename "$CORE"); CLI_BASE=$(basename "$CLI")
case "$CORE_BASE" in glyphsift-core-*.crate) ;; *) die "the first file must be named glyphsift-core-<version>.crate (got $CORE_BASE)" ;; esac
case "$CLI_BASE" in glyphsift-cli-*.crate) ;; *) die "the second file must be named glyphsift-cli-<version>.crate (got $CLI_BASE)" ;; esac
V=${CORE_BASE#glyphsift-core-}; V=${V%.crate}
[ "${CLI_BASE#glyphsift-cli-}" = "$V.crate" ] || die "the two crates have different versions ($CORE_BASE, $CLI_BASE)"
case "$V" in ''|*[!0-9A-Za-z.+-]*) die "bad version '$V'" ;; esac
for d in "$WORK" "$ROOT"; do
  if [ -e "$d" ] && [ -n "$(ls -A "$d" 2>/dev/null)" ]; then die "$d already exists and is not empty"; fi
  mkdir -p "$d"
done
WORK=$(cd "$WORK" && pwd -P); ROOT=$(cd "$ROOT" && pwd -P)
EXE=""; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) EXE=.exe ;; esac

echo "== 1. unpack the packaged CLI crate"
mkdir -p "$WORK/src" "$WORK/vendor"
tar -xzf "$CLI" -C "$WORK/src"
SRC=$WORK/src/glyphsift-cli-$V
[ -f "$SRC/Cargo.toml" ] || die "$CLI_BASE did not unpack to glyphsift-cli-$V/Cargo.toml"
if [ -f "$SRC/Cargo.lock" ]; then echo "the packaged crate carries its own Cargo.lock"; else die "the packaged CLI crate has no Cargo.lock, so --locked cannot hold"; fi

echo "== 2. directory source: third-party crates by cargo vendor --locked, glyphsift-core from the packaged .crate"
cargo vendor --locked "$WORK/vendor" > "$WORK/vendor.log" 2>&1 || { cat "$WORK/vendor.log" >&2; die "cargo vendor --locked failed"; }
[ ! -e "$WORK/vendor/glyphsift-core" ] || die "the vendor step wrote glyphsift-core: a workspace crate must come from the packaged file only"
tar -xzf "$CORE" -C "$WORK/vendor"
[ -f "$WORK/vendor/glyphsift-core-$V/Cargo.toml" ] || die "$CORE_BASE did not unpack to glyphsift-core-$V/Cargo.toml"
node scripts/release/dirsource-checksum.mjs "$(to_native "$CORE")" "$(to_native "$WORK/vendor/glyphsift-core-$V")"

echo "== 3. cargo config: crates-io replaced by the directory, offline"
cat > "$WORK/config.toml" <<TOML
[net]
offline = true

[source.crates-io]
replace-with = "glyphsift-dirsrc"

[source.glyphsift-dirsrc]
directory = "$(to_native "$WORK/vendor")"
TOML

echo "== 4. cargo install --path <unpacked cli crate> --offline --locked --root <fresh root>"
LOG=$WORK/install.log
set +e
( cd "$SRC" && cargo install --path . --offline --locked --root "$(to_native "$ROOT")" --config "$(to_native "$WORK/config.toml")" ) > "$LOG" 2>&1
RC=$?
set -e
strip_ansi < "$LOG" > "$WORK/install.plain.log"
sed 's/^/  | /' "$WORK/install.plain.log" | tail -25
[ "$RC" -eq 0 ] || die "the install exited $RC"
grep -qE "^ *Compiling glyphsift-core v$V" "$WORK/install.plain.log" || die "the log has no 'Compiling glyphsift-core v$V' line"
grep -qE '^ *Installed package' "$WORK/install.plain.log" || die "the log has no 'Installed package' line"
if grep -E '^ *(Downloading|Downloaded|Updating)' "$WORK/install.plain.log"; then die "the log shows a registry download or index update: a crate was not taken from the directory source"; fi
echo "ok: no 'Downloading', 'Downloaded' or 'Updating' line: glyphsift-core $V was built from the packaged .crate, nothing came from a registry"
[ -x "$ROOT/bin/glyphsift$EXE" ] || die "$ROOT/bin/glyphsift$EXE was not installed"
echo "installed: $ROOT/bin/glyphsift$EXE"
