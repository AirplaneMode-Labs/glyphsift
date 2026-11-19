#!/usr/bin/env bash
# Self-test of the cargo test log parser in tests/scripts/lib.sh (cargo_bin_passed, cargo_failed_total, strip_ansi), the one
# tests/scripts/sdist-locked.sh uses to prove that crates/glyphsift-core/tests/corrupt.rs and gate_noise.rs ran in the unpacked sdist.
#
#   tests/scripts/cargo-test-log.sh
#
# Why this exists (CI run 44580204699 at 84b5c3d, job "packaging dry runs", Linux): sdist-locked.sh passed on macOS and failed on Ubuntu with
# "FAIL - tests/corrupt.rs ran in the unpacked sdist (passed: 'none')" although `cargo test` exited 0 with 0 failed. The workflow sets
# CARGO_TERM_COLOR=always (ci.yml, top-level env), and with it cargo writes its status word in colour even into a file:
#
#   ESC[1mESC[92m     RunningESC[0m tests/corrupt.rs (target/debug/deps/corrupt-<hash>)
#
# so the awk that looked for the literal text "Running tests/corrupt.rs" never found the line and printed nothing. A Mac shell has no
# CARGO_TERM_COLOR, so the log was plain there. The Windows runner adds a second difference that the same literal would have hit with or
# without colour: its Running line uses backslashes and a .exe path (`tests\corrupt.rs (target\debug\deps\corrupt-<hash>.exe)`).
#
# The fixtures below take the shape of each line from the logs of that run (the Linux, macOS and Windows legs of the `check` job, whose
# `cargo test --locked` printed these Running lines) and from `cargo test` on this Mac with CARGO_TERM_COLOR=never; the binary hashes,
# test counts and timings are illustrative. The test needs no cargo, no network and no built sdist, so the `check` job runs it on all
# three operating systems.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

E=$(printf '\033')                      # the ESC byte, without relying on $'' or printf \e
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/glyphsift-cargolog.XXXXXX") || exit 1
SCRATCH=$(cd "$SCRATCH" && pwd -P)
# Only the mktemp directory created above is ever removed: the guard refuses any other shape of path.
cleanup() { case "$SCRATCH" in /*/glyphsift-cargolog.??????) rm -rf "$SCRATCH" ;; esac; }
trap cleanup EXIT

# --- fixtures --------------------------------------------------------------------------------------
# Linux runner (ubuntu-latest), CARGO_TERM_COLOR=always: coloured Running word, forward slashes.
cat > "$SCRATCH/linux-colour.log" <<EOF
${E}[1m${E}[92m     Running${E}[0m tests/corrupt.rs (target/debug/deps/corrupt-5abee9fe384abd85)

running 28 tests
test a_seeded_run_is_reproducible ... ok

test result: ok. 28 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 2.39s

${E}[1m${E}[92m     Running${E}[0m tests/gate.rs (target/debug/deps/gate-594db180b26c5ea1)

running 9 tests
test result: ok. 9 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.12s

${E}[1m${E}[92m     Running${E}[0m tests/gate_noise.rs (target/debug/deps/gate_noise-1cd60dd4e0b00ea9)

running 3 tests
test the_recommended_noise_holds_nearly_every_three_line_chunk ... ok
test the_doc_tables_are_these_exact_hold_counts ... ok
test nothing_is_held_on_the_clean_corpus_holds_only_grow_with_noise_and_nothing_is_not_scored ... ok

test result: ok. 3 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 9.84s

EOF
# This Mac with CARGO_TERM_COLOR=never (what the local gates always saw): plain text, forward slashes.
cat > "$SCRATCH/mac-plain.log" <<'EOF'
     Running tests/corrupt.rs (target/debug/deps/corrupt-58eb7367fa2643d3)

running 28 tests
test result: ok. 28 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 2.39s

     Running tests/gate_noise.rs (target/debug/deps/gate_noise-eef770e76d26d54b)

running 3 tests
test result: ok. 3 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 5.13s

EOF
# Windows runner, CARGO_TERM_COLOR=always: coloured Running word, backslashes and .exe, and (in Git Bash) a CR may end a line.
{
  printf '%s\r\n' "${E}[1m${E}[92m     Running${E}[0m tests\\corrupt.rs (target\\debug\\deps\\corrupt-5abee9fe384abd85.exe)"
  printf '%s\r\n' "" "running 28 tests" "test result: ok. 28 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 2.90s" ""
  printf '%s\r\n' "${E}[1m${E}[92m     Running${E}[0m tests\\gate_noise.rs (target\\debug\\deps\\gate_noise-e4e10f4109c6d02e.exe)"
  printf '%s\r\n' "" "running 3 tests" "test result: ok. 3 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 11.20s" ""
} > "$SCRATCH/windows-colour.log"
# libtest itself coloured (`cargo test -- --color=always`): the summary word is wrapped as well.
cat > "$SCRATCH/libtest-colour.log" <<EOF
${E}[1m${E}[92m     Running${E}[0m tests/corrupt.rs (target/debug/deps/corrupt-aaaaaaaaaaaaaaaa)

running 28 tests
test result: ${E}[32mok${E}[0m. 28 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 2.39s

${E}[1m${E}[92m     Running${E}[0m tests/gate_noise.rs (target/debug/deps/gate_noise-bbbbbbbbbbbbbbbb)

running 3 tests
test result: ${E}[32mok${E}[0m. 3 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 5.13s
EOF

# --- the parser, on every runner's format ------------------------------------------------------------
echo "== both shipped binaries are found, with their passed count, in each runner's log"
for fx in linux-colour mac-plain windows-colour libtest-colour; do
  expect_eq "$fx: tests/corrupt.rs passed 28"    28 "$(cargo_bin_passed "$SCRATCH/$fx.log" corrupt)"
  expect_eq "$fx: tests/gate_noise.rs passed 3"   3 "$(cargo_bin_passed "$SCRATCH/$fx.log" gate_noise)"
  expect_eq "$fx: no test failed"                 0 "$(cargo_failed_total "$SCRATCH/$fx.log")"
done

echo "== the parser still refuses a binary that did not run, ran nothing or failed"
# Without --features corrupt cargo skips both binaries silently: no Running line for them at all.
cat > "$SCRATCH/skipped.log" <<EOF
${E}[1m${E}[92m     Running${E}[0m unittests src/lib.rs (target/debug/deps/glyphsift_core-775ff96230bb6cbe)

running 120 tests
test result: ok. 120 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.20s

${E}[1m${E}[92m     Running${E}[0m tests/gate.rs (target/debug/deps/gate-594db180b26c5ea1)

running 9 tests
test result: ok. 9 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.12s
EOF
expect_eq "skipped (feature off): corrupt prints nothing"    "" "$(cargo_bin_passed "$SCRATCH/skipped.log" corrupt)"
expect_eq "skipped (feature off): gate_noise prints nothing" "" "$(cargo_bin_passed "$SCRATCH/skipped.log" gate_noise)"
expect_eq "tests/gate.rs is not mistaken for tests/gate_noise.rs (and the reverse)" "9" "$(cargo_bin_passed "$SCRATCH/skipped.log" gate)"
expect_eq "a log that mentions the name only in a path is not a Running line" "" "$(printf 'warning: tests/corrupt.rs (not run)\ntest result: ok. 5 passed; 0 failed\n' > "$SCRATCH/mention.log"; cargo_bin_passed "$SCRATCH/mention.log" corrupt)"

# The binary ran and found no test: the count is 0, and sdist-locked.sh requires at least 1.
cat > "$SCRATCH/zero.log" <<EOF
${E}[1m${E}[92m     Running${E}[0m tests/corrupt.rs (target/debug/deps/corrupt-cccccccccccccccc)

running 0 tests

test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
EOF
expect_eq "ran 0 tests: prints 0, not a pass" 0 "$(cargo_bin_passed "$SCRATCH/zero.log" corrupt)"

# A failing binary is never reported as passed, whatever else it says.
cat > "$SCRATCH/failed.log" <<EOF
${E}[1m${E}[92m     Running${E}[0m tests/corrupt.rs (target/debug/deps/corrupt-dddddddddddddddd)

running 28 tests
test result: FAILED. 27 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out; finished in 2.39s
EOF
expect_eq "a FAILED summary prints nothing" "" "$(cargo_bin_passed "$SCRATCH/failed.log" corrupt)"
expect_eq "the failed count is read from it" 1 "$(cargo_failed_total "$SCRATCH/failed.log")"

# A binary that crashes before its summary must not borrow the next binary's summary.
cat > "$SCRATCH/crash.log" <<EOF
${E}[1m${E}[92m     Running${E}[0m tests/corrupt.rs (target/debug/deps/corrupt-eeeeeeeeeeeeeeee)

running 28 tests
error: test failed, to rerun pass \`-p glyphsift-core --test corrupt\`
${E}[1m${E}[92m     Running${E}[0m tests/gate_noise.rs (target/debug/deps/gate_noise-ffffffffffffffff)

running 3 tests
test result: ok. 3 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 5.13s
EOF
expect_eq "a crash before the summary prints nothing for that binary" "" "$(cargo_bin_passed "$SCRATCH/crash.log" corrupt)"
expect_eq "and the next binary keeps its own count" 3 "$(cargo_bin_passed "$SCRATCH/crash.log" gate_noise)"

echo "== several binaries: the failed count is the sum"
cat > "$SCRATCH/sum.log" <<'EOF'
test result: ok. 10 passed; 0 failed; 0 ignored
test result: FAILED. 1 passed; 2 failed; 0 ignored
test result: FAILED. 0 passed; 3 failed; 0 ignored
EOF
expect_eq "2 + 3 failed" 5 "$(cargo_failed_total "$SCRATCH/sum.log")"
: > "$SCRATCH/empty.log"
expect_eq "an empty log has 0 failed (the exit code and the per-binary counts are what catch it)" 0 "$(cargo_failed_total "$SCRATCH/empty.log")"

echo "== strip_ansi"
expect_eq "colour codes and a CR are removed, other text is kept" "     Running tests/x.rs (a\\b)" \
  "$(printf '%s\r\n' "${E}[1m${E}[92m     Running${E}[0m tests/x.rs (a\\b)" | strip_ansi)"
expect_eq "a bare ESC-less line is unchanged" "test result: ok. 1 passed" "$(printf 'test result: ok. 1 passed\n' | strip_ansi)"

echo "== the fault, reproduced: the S6 pattern finds nothing in the runner's coloured line"
old_awk() { awk -v b="tests/$2.rs" 'index($0,"Running " b){f=1;next} f&&/^test result:/{match($0,/[0-9]+ passed/);print substr($0,RSTART,RLENGTH-7);exit}' "$1"; }
expect_eq "S6 awk on the plain Mac log: 28 (why it passed on this Mac)" 28 "$(old_awk "$SCRATCH/mac-plain.log" corrupt)"
expect_eq "S6 awk on the Linux runner's coloured log: nothing (why CI went red)" "" "$(old_awk "$SCRATCH/linux-colour.log" corrupt)"
expect_eq "S6 awk on the Windows log: nothing" "" "$(old_awk "$SCRATCH/windows-colour.log" corrupt)"

echo "== sdist-locked.sh uses the parser, not its own awk, and does not turn colour off"
SL=$REPO/tests/scripts/sdist-locked.sh
expect_eq "it calls cargo_bin_passed for each shipped binary" 1 "$(grep -c 'cargo_bin_passed "\$SCRATCH/test.log" "\$bin"' "$SL")"
expect_eq "it calls cargo_failed_total for the failed count" 1 "$(grep -c 'cargo_failed_total "\$SCRATCH/test.log"' "$SL")"
expect_eq "it has no inline awk over test.log" 0 "$(grep -vE '^[[:space:]]*#' "$SL" | grep -c 'awk .*test\.log')"
expect_eq "it does not set CARGO_TERM_COLOR (CI's colour must reach the parser)" 0 "$(grep -vE '^[[:space:]]*#' "$SL" | grep -c 'CARGO_TERM_COLOR')"

echo "== live: this machine's own cargo test log (GLYPHSIFT_LIVE_CARGO_LOG=1; the CI check job sets it on ubuntu, macos and windows)"
if [ "${GLYPHSIFT_LIVE_CARGO_LOG:-0}" = 1 ]; then
  # The two feature-gated binaries of glyphsift-core, run in the repository itself (the sdist is not needed to prove the parser).
  # The output goes to a file, as in sdist-locked.sh, and keeps whatever CARGO_TERM_COLOR the environment sets.
  ( cd "$REPO" && cargo test --locked --no-fail-fast -p glyphsift-core --features corrupt --test corrupt --test gate_noise ) > "$SCRATCH/live.log" 2>&1
  rc=$?
  expect_eq "cargo test of the two feature-gated binaries exits 0" 0 "$rc"
  if [ "$rc" -ne 0 ]; then strip_ansi < "$SCRATCH/live.log" | tail -15; fi
  if [ "${CARGO_TERM_COLOR:-}" = always ]; then
    # Proves the run really was in the condition that broke the S6 parser, not just that the variable was set.
    if grep -q "$E" "$SCRATCH/live.log"; then ok "CARGO_TERM_COLOR=always put escape bytes into the log file"; else fail "CARGO_TERM_COLOR=always put escape bytes into the log file"; fi
  fi
  for bin in corrupt gate_noise; do
    N=$(cargo_bin_passed "$SCRATCH/live.log" "$bin")
    if [ "${N:-0}" -ge 1 ] 2>/dev/null; then ok "live: tests/$bin.rs ran and $N tests passed"; else
      fail "live: tests/$bin.rs ran (passed: '${N:-none}')"
      grep -m1 'Running' "$SCRATCH/live.log" | cat -v | sed 's/^/    raw: /'
    fi
  done
  expect_eq "live: 0 tests failed" 0 "$(cargo_failed_total "$SCRATCH/live.log")"
else
  echo "skip - no live cargo run (set GLYPHSIFT_LIVE_CARGO_LOG=1 to run cargo test here and parse its own log)"
fi

finish
