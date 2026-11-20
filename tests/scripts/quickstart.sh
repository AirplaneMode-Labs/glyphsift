#!/usr/bin/env bash
# D3-04: the README's "## Try it in two minutes" runs (Sprint 7; TD-115, TD-116). The blocks are extracted and executed by tests/scripts/quickstart.mjs: a
# static pre-check, then the setup block from the repository root, then the install, file and run blocks in a fresh empty directory outside the clone with a
# scrubbed environment, then the output compared with the expect block. If any block fails, or the output differs by one character, this test is red.
#
#   tests/scripts/quickstart.sh
#   QUICKSTART_SELF_ONLY=1 tests/scripts/quickstart.sh    only the self-test and the prose checks (no build): for a quick local look
#
# Needs: Rust 1.98 with the wasm32 target, wasm-bindgen 0.2.129 and wasm-opt (scripts/install-wasm-tools.sh), Node 22, Python 3.9+, and maturin 1.16.0 on PATH or in the
# venv named by GLYPHSIFT_TOOLS_VENV (CI makes it from tools/ci/requirements.txt by hash). No model, no test key, no download by the quick start itself.
#
#  A. the harness self-test: the parser and the static pre-check refuse every forbidden thing (http, https, curl, wget, a pipe into a shell, sudo, npx, the test-key
#     flags, rfc8032, unsafe-, a CSP edit, a plain block that is not the clone line, an unknown tag, a missing block kind);
#  B. the prose around the blocks: it says what is needed, that nothing is downloaded, the Windows mapping in one sentence, and links the live demo;
#  C. the real run, unless QUICKSTART_SELF_ONLY=1.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1
command -v node >/dev/null || { fail "node not found: Node 22 is required"; finish; exit 1; }

echo "== A. harness self-test"
node tests/scripts/quickstart.mjs --self-test > "${TMPDIR:-/tmp}/quickstart-self-$$.log" 2>&1; RC=$?
grep -E '^FAIL|self-test:' "${TMPDIR:-/tmp}/quickstart-self-$$.log" | sed 's/^/    /'
expect_eq "the quickstart harness self-test passes" 0 "$RC"
rm -f "${TMPDIR:-/tmp}/quickstart-self-$$.log"

echo "== B. the prose of the section"
SEC=$(awk '/^## Try it in two minutes$/{on=1; print; next} on && /^## /{exit} on{print}' README.md)
if [ -n "$SEC" ]; then ok "README.md has '## Try it in two minutes'"; else fail "README.md has '## Try it in two minutes'"; finish; exit 1; fi
expect_eq "the section comes right after '## Status' and before '## Install'" "Status Try it in two minutes Install" "$(grep -E '^## (Status|Try it in two minutes|Install)$' README.md | sed 's/^## //' | tr '\n' ' ' | sed 's/ $//')"
prose() { if printf '%s\n' "$SEC" | tr '\n' ' ' | sed 's/  */ /g' | gq -F -- "$1"; then ok "the section says $2"; else fail "the section says $2 ($1)"; fi; }
prose "no model" "that no model is involved"
prose "downloads Rust crates from crates.io once (57 registry crates in \`Cargo.lock\`)" "that the setup block downloads Rust crates from crates.io once, with the count (BUG-T1-S7-11)"
prose "the install and run blocks run offline with no model, key or account" "that the install and run blocks run offline with no model, key or account"
expect_eq "the 57 in the README is the number of registry crates in Cargo.lock" 57 "$(grep -c 'source = \"registry' Cargo.lock)"
expect_eq "the section no longer says the quick start downloads nothing" 0 "$(printf '%s\n' "$SEC" | tr '\n' ' ' | grep -cF 'downloads nothing')"
prose "nothing is published" "that nothing is published, so every command builds from the clone"
prose "Rust 1.98" "which Rust is needed"
prose "Node 22" "which Node is needed"
prose "maturin 1.16.0" "which maturin is needed"
prose "On Windows" "how Windows differs"
prose '`.venv/Scripts/`' "that .venv/bin/ is .venv/Scripts/ on Windows"
prose "https://airplanemode-labs.github.io/glyphsift/" "where the live demo is (the browser needs no install)"
prose "tests/scripts/quickstart.sh" "which test runs the blocks"
prose "not measured on 8 GB" "that no 8 GB figure is claimed"
expect_eq "the section holds no 'published' claim other than 'nothing is published'" 0 "$(printf '%s\n' "$SEC" | grep -iE 'is published|audited|compliant|production-ready' | grep -vcF 'nothing is published')"
expect_eq "the section names no test key" 0 "$(printf '%s\n' "$SEC" | grep -ciE 'test key|test-key|rfc8032')"

echo "== C. every block, from the built artefacts"
if [ "${QUICKSTART_SELF_ONLY:-0}" = 1 ]; then
  echo "na   - the real run is skipped on request (QUICKSTART_SELF_ONLY=1); CI and the sprint gates run it"
else
  node tests/scripts/quickstart.mjs > "${TMPDIR:-/tmp}/quickstart-run-$$.log" 2>&1; RC=$?
  sed 's/^/    /' "${TMPDIR:-/tmp}/quickstart-run-$$.log" | tail -40
  rm -f "${TMPDIR:-/tmp}/quickstart-run-$$.log"
  expect_eq "every block ran and the output matched the expect block" 0 "$RC"
fi
finish
