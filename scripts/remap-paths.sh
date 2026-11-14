# Source this file (it is not run): it appends --remap-path-prefix flags to RUSTFLAGS so the builder's
# home directory, cargo and rustup directories and checkout path do not end up in the wheel, the WASM or
# the CLI (panic locations and debug paths embed them). Any RUSTFLAGS already set are kept; nothing in
# ~/.cargo/config is read or edited.
#
#   . scripts/remap-paths.sh      # from the repository root, after `cd`
_gs_root=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)
_gs_cargo=${CARGO_HOME:-$HOME/.cargo}
_gs_rustup=${RUSTUP_HOME:-$HOME/.rustup}
RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }--remap-path-prefix=$_gs_cargo=/cargo --remap-path-prefix=$_gs_rustup=/rustup --remap-path-prefix=$_gs_root=/glyphsift"
export RUSTFLAGS
unset _gs_root _gs_cargo _gs_rustup
