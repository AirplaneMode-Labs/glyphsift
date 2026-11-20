# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.3] - 2026-11-20 (untagged)

Sprint 7 (20 Nov 2026, untagged), glyphsift **0.1.3** (TD-107): release readiness, so that publishing becomes a short list of the owner's own steps (`docs/RELEASING.md`). 0.1.0, 0.1.1 and 0.1.2 were never tagged; 0.1.3 supersedes them.
Nothing is published, signed or tagged. The scoring, the weights, the report spec (`glyphsift.report/0.2`), the gate rules, the benchmark CSV and SVG and every determinism sample are byte-identical to 0.1.2: `bench --verify` passes. Sprint 7 is an
owner-requested addition; it has no row in the plan documents and creates no gate-1 evidence.

Owner decision, 20 Nov 2026: every benchmark glyphsift quotes is published in this repository as a raw file with its date, commit, machine and method. No rule, weight, report, gate or determinism byte changed: the score CSV and SVG are byte-identical
to 0.1.3 (`bench --verify` passes, three fresh `bench` runs equal the committed files), and nothing was measured on an 8 GB laptop (not measured on 8 GB).

### Added

- `release-rehearsal (<os>)` (D3-02, TD-106, TD-118), a CI job on ubuntu, macos and windows that replaces the Sprint 4 `wheels` job (`wheel and sdist (<os>)`). `scripts/release/rehearse.sh` builds the artefacts as a release would (`scripts/release/build-artefacts.sh`: the npm
  tarball, this platform's wheel with `maturin build --release --locked`, on Linux the sdist, and the packaged crates `glyphsift-core` and `glyphsift-cli` from `cargo package --workspace --locked`); installs each built file, never the source tree, into a fresh place with no
  sibling repository and no registry (an empty npm project with `npm_config_offline=true`, a fresh cache and `--ignore-scripts`; a fresh `.venv` with `PIP_NO_INDEX=1`; on Linux a wheel built from the unpacked sdist alone; the CLI built by `cargo install --offline --locked` from the unpacked packaged crates,
  `glyphsift-core` taken from the packaged file through a directory source made by `cargo vendor --locked`, `scripts/release/install-crate-offline.sh`); asserts one real call each (a clean and a corrupted Devanagari sample must give the report and the `glyphsift.gate/0.1` bytes committed under `tests/determinism`,
  verdicts pass and hold, `scripts/release/check-installed.mjs` and `.py`); then signs a `glyphsift-rehearsal` manifest with the published RFC 8032 test key (deterministic with `SOURCE_DATE_EPOCH`, no expiry, TD-121), verifies it with the explicit flag and proves the refusals by exit code, first stderr line and JSON reason: `test_key_refused`
  without the flag, `no_trusted_key` against the committed empty `docs/release-keys.json`, `expect_id_required`, `test_key_flag_misuse`, `test_key_release_id` (R1) and `artifact_hash_mismatch` for a changed artefact. The upload is `dist-release/` and `dist-release-report/` only, named `REHEARSAL-test-key-NOT-A-RELEASE-glyphsift-<os>-<sha>`, kept 3 days, after
  `rehearse.sh assert-dir` has shown that nothing but the manifest entries, the manifest and `SHA256SUMS` is there. Hashed tools, `--locked`, no cache, `contents: read`, no secret. Run on macOS twice with the same `SOURCE_DATE_EPOCH`: `SHA256SUMS` and `release-manifest.json` byte-identical.
  Tests: `tests/scripts/rehearse.sh` (62 checks: synthetic artefacts, a missing tool, seven kinds of misbehaving tool, `assert-dir` refusals, unsafe paths) and the new rules K of `tests/scripts/ci-policy.sh`.
- The release tool vendored from runtime's spec 0.6.1 (D3-01, TD-103, TD-104): `scripts/release/release-tool.mjs` byte for byte, `scripts/release/VENDORED.json` (source, spec release, sha256, the digest of the shared vectors) and the 31 shared release vectors under `scripts/release/vectors/`, all `-text` in `.gitattributes`.
  `tests/scripts/release-tool-vendored.sh` checks the pins and the bundle's allowlist, runs every case of `release.json` through the vendored copy (`tests/scripts/release-tool-cases.mjs`, 35 cases on macOS and Linux, the junction case on Windows; the rehearsal runs them on all three) and shows that
  `scripts/release-manifest.mjs` and `release-tool manifest` write byte-identical output for `glyphsift-release`.
- `.github/workflows/publish.yml` and `docs/RELEASING.md` (D3-03, TD-105, TD-122, TD-123): a publish workflow that only the owner can start and nobody has run. `workflow_dispatch` only, no inputs, main of this repository only; six locks (repository and ref guard; the `release` environment with the owner as reviewer; the variable
  `RELEASE_PUBLISH_ARMED`; the owner's signed manifest from the GitHub release verified against `docs/release-keys.json`; registry credentials only as secrets of that environment; `RELEASE_KEY_ID` equal to the one committed key, S1-129), three bindings (tag `v<version>` peels to this commit; the manifest says `glyphsift-release`, this version and no
  expiry; no registry holds the version), then an attestation of the exact files, then publishing from the exact files the verified manifest lists (npm with `--provenance`, PyPI with attestations, crates after their re-packaged digests are compared). `scripts/release/publish-guard.sh` holds the checks and `tests/scripts/publish-guard.sh` proves
  each refusal with stand-ins for `gh` and `curl` (78 checks, 117 after fix round 1); `scripts/release/publish-dry-run.sh` (`npm publish --dry-run`, `cargo publish --dry-run --workspace --locked`, the wheel metadata) is run by the rehearsal on three systems. Rules L of `tests/scripts/ci-policy.sh` pin every one of these and each single mutation of the workflow turns one red.
- `docs/release-keys.json`, committed with an empty key list until the owner adds the real public key (`{"spec":"airplanemode.release-keys/0.1","keys":[]}`); `docs/RELEASING.md` lists, in order, only the steps that are the owner's, each with the reason the team cannot do it.
- `## Try it in two minutes` in the README (D3-04, TD-115, TD-116): a clone, a build, a fresh venv and a fresh npm project, a clean and a noisy line scored from Python, Node and the command line, no model and no download. `tests/scripts/quickstart.sh` (with `tests/scripts/quickstart.mjs`) extracts every block, runs a static pre-check
  (no http, https, curl, wget, pipe into a shell, sudo, npx, test-key flag or CSP edit), runs the blocks from the built files in a fresh directory with a scrubbed environment and compares the output with the expect block; eleven single-line breaks of the section each turn it red. A `Live demo:` line is within the first 12 lines of the README, checked by `tests/scripts/readme-claims.sh`.
- Issue forms (`bug_report.yml` with a required no-real-documents checkbox, `feature_request.yml`, `config.yml` with blank issues off and a link to `SECURITY.md`), a `CONTRIBUTING.md` that names the release path, and `drafts/good-first-issues/glyphsift.md` (texts only; nothing is filed) (D3-04, TD-117).
- `docs/writeup-0.1.3-draft.md`, marked draft, not published (D3-06).
- `tests/scripts/cargo-test-log.sh` (added after the Sprint 6 push, folded in from the old [Unreleased] block; tests first, red then green): the self-test of the colour- and Windows-safe cargo log parser on the line format of each runner, and with `GLYPHSIFT_LIVE_CARGO_LOG=1` on the real `cargo test` log of the machine it runs on
  (the `check` job runs it on ubuntu, macos and windows). `tests/scripts/run-all.sh` picks it up.
- `docs/benchmarks/` with a `README.md` index (what each file is, its date, commit and machine, the exact command that reproduces it, the standing line that nothing here is measured on an 8 GB laptop unless a file says so, and the list of figures whose raw data is not kept) and eight raw files,
  all measured at 3c0bb4d on 20 Nov 2026 on the Apple M5 Pro, 48 GB except the CI record: `score-vs-noise.csv` (a byte-identical copy of `docs/score-vs-noise.csv`, which the tests, the chart and the source package still read) with `score-vs-noise.provenance.json` (SHA-256 of the CSV and SVG, three byte-identical fresh runs, `bench --verify` PASS, the bench
  wall-clock times), `throughput-m5pro-48gb.json` (all five runs of every measurement), `demo-1mib-m5pro-48gb.json` (one run in headless Chrome 157.0.8103.80), `wasm-linearity-m5pro-48gb.json` (ratio 1.99), `gate-holds.json` (the hold counts of `docs/gate.md`), `joiner-sites.json` (the README's 599 of 807) and
  `ci-run-43667702791.json` (the sizes CI run 43667702791 printed for its wheels, sdist and npm tarball, copied from its logs and artifact list before the artifacts expire on 22 Nov 2026).
- The commands that write them: `scripts/lib/bench-provenance.mjs` (the shared envelope: schema, date, commit, whether the build inputs were modified, machine as CPU model and RAM only, environment, method, command, data); `--json` on `scripts/throughput.mjs`; `--bench-json` on `tests/wasm/run_wasm_safety.mjs` and `tests/demo/check_demo.mjs` (both write only when every check passed);
  `scripts/record-benchmarks.mjs score-vs-noise|joiner-sites|gate-holds`.
- `tests/scripts/benchmarks-raw.sh` (148 checks): the envelope, the index, a 40-hex commit, `build_inputs_modified` false, a machine label that is model and RAM only, no builder path, no file over 5 MB, the CSV copy byte-identical, the SHA-256 and row counts in the provenance file, the sizes of `docs/release.md` against the CI file; and nine mutations of a scratch copy that each turn it red.
- The demo footer links `docs/benchmarks/` on GitHub ("Benchmark raw data", a plain link, no request, the CSP unchanged); `tests/demo/check_demo.mjs` pins the link (250 checks).

### Changed

- Version 0.1.3 everywhere (workspace, crates, `Cargo.lock`, wheel, npm package).
- `scripts/package-npm.sh` takes `PACKAGE_NPM_PACK_ONLY=1` (stop after the builder-path gate with the tarball written) and `PYTHON` (the interpreter for that gate; a Windows runner has `python`, not always `python3`). The default behaviour is unchanged.
- `tests/docs_numbers.py` also requires `docs/what-glyphsift-measures.md` to name the workspace version, so the page the outreach drafts quote cannot lag the release; the page's Status line is re-read in Sprint 7 and no number on it changed.
- Demo: a Sprint 7 status line and one new line in "What this demo does not do yet" (no signing key, no tag, the release path rehearsed in CI with a public test key only); no CSP change, 0 requests when idle (249 checks).
- `.gitignore`: `/dist-release/`, `/dist-release-report/` and `*.crate`.
- `docs/release.md`: the definition-of-done rows say what the rehearsal and the publish workflow now prove and what stays open (the 8 GB figure, the real key, reserved names, the configured environment, publishing, the tag, the write-up).
- Sprint 7 fix round 1 (D3, FR1-REVENDOR): the release tool re-vendored from runtime's re-landed spec 0.6.1 (D1/RELANDED-FR1.txt): `scripts/release/release-tool.mjs` sha256 `81583057...` (was `57c2af90...`), `scripts/release/VENDORED.json` updated, the 31 shared vectors unchanged byte for byte (`diff -r` against runtime's `spec/vectors/release` is empty); `tests/scripts/release-tool-vendored.sh` (25 checks) and `release-tool-cases.mjs` (35 of 35 on macOS; the junction case is Windows only) pass, and two sign phases with the same `SOURCE_DATE_EPOCH` are byte-identical.
- The README's throughput figures are re-measured and replace the Sprint 3 and Sprint 5 ones, whose logs record no commit (raw data not kept): native `check` 66 ms (was 61 and 67), `validate()` 238 ms (was 220 and 234), `score_ppm()` 81 ms (was 74 and 80), `gate()` 40 ms (was 40), native `gate` 17 ms (was 17), the demo 1,602 ms (was 1,462, one run);
  the 5,000-mark against 2,500-mark ratio is quoted as 1.99 (was "about twice"); the benchmark takes 546 ms (was "about one second"). The 1 MiB input is the same file (SHA-256 `3336ba4c...`). The figures of earlier sprints that stay in `CHANGELOG.md`, `docs/release.md` and `docs/benchmarks/README.md` are marked "raw data not kept".
- `tests/docs_numbers.py` also re-reads, from `docs/benchmarks/`, every row of the README's score tables (mixed mean, minimum and maximum, the twelve triggering families, the seven blind spots, both ways), the recall statement, "599 of 807", "285 of 288", the linearity ratio, every row and prose count of the two hold tables of `docs/gate.md`, and every `N ms` figure in the README, the CHANGELOG
  and `docs/*.md` (a figure with no matching value fails unless its paragraph says "raw data not kept"); it now reads the benchmark CSV from `docs/benchmarks/score-vs-noise.csv` and requires it to equal `docs/score-vs-noise.csv` byte for byte.
- `tests/scripts/readme-claims.sh` section C reads the committed raw files instead of a log outside the repository, so it runs on every checkout, CI included (it used to print "not applicable" there): the five timings, the demo line, the table header's input, machine and operating system, the commit, date, Node and Chrome versions, and the benchmark time.
- README Benchmarks and Limitations, `docs/gate.md`, `docs/what-glyphsift-measures.md`, `docs/release.md` and `docs/writeup-0.1.3-draft.md` point at `docs/benchmarks/`; the owner's 8 GB steps in `docs/release.md` and `docs/RELEASING.md` produce raw files (`--json`, `--bench-json`) that are committed before the README column is filled.

### Fixed

- S1-118 follow-up, the one red job of that run (`packaging dry runs`, Linux): `tests/scripts/sdist-locked.sh` printed `FAIL - tests/corrupt.rs ran in the unpacked sdist (passed: 'none')` and the same for `gate_noise.rs` although
  `cargo test` exited 0 with 0 failed. Cause: `ci.yml` sets `CARGO_TERM_COLOR=always`, and cargo then colours the status word of each `Running` line even in a log file
  (`ESC[1mESC[92m     RunningESC[0m tests/corrupt.rs (...)`), so the awk that looked for the literal `Running tests/corrupt.rs` found no line and printed nothing. The shell on the Mac has no such variable, so the log was plain there.
  Reproduced on macOS by running the committed script with `CARGO_TERM_COLOR=always` (the same two FAIL lines, `31 passed, 2 failed`). The Windows runner would have failed the same literal even without colour: its Running line is
  `tests\corrupt.rs (target\debug\deps\corrupt-<hash>.exe)`. The log is now read through `strip_ansi`, `cargo_bin_passed` and `cargo_failed_total` in `tests/scripts/lib.sh`, which drop colour codes and CRs, accept both path spellings, take the
  binary's own `test result: ok.` line only (a binary that did not run, crashed before its summary, ran 0 tests or failed never counts as passed), and the script prints the Running and summary lines when a binary is not found, so a next red names its cause.
  The check is not weaker: with `--features corrupt` removed from the script, cargo skips both binaries and it still fails for both.
- No other script of this repository reads cargo or libtest output by its text (`ci-policy.sh` greps `cargo doc` output for the word `collision`, which colour cannot split).

- The one red job of CI run 44580204699 is fixed at the head of Sprint 6 (`6859d81`, `f9e88f4`, run 44584716730 green on all 15 jobs, read with `gh` on 20 Nov 2026): see the entry above.
- Sprint 7 fix round 1 (D3, FR1): BUG-T3-S7-01 / S1-130: `publish.yml` passed `npm publish "verified/<name>.tgz"`, and npm reads a bare `a/b` as the GitHub shorthand user/repo (npm's own `npm-package-arg` resolves it as a hosted `github:verified/...`
  spec, a third party's repository), so the first real publish would have tried to publish that. The argument is now `"./verified/$(cat lists/npm.txt)"` (type `file`), `scripts/release/publish-dry-run.sh` runs the identical string from a scratch directory laid out like the job's
  (`verified/`, `lists/npm.txt`), `ci-policy.sh` rule M1 requires every `npm publish` argument in every workflow to start with `./` or `/` and the two strings to be equal, and `tests/scripts/npm-publish-arg.sh` asks npm's resolver (red: `git`, green: `file`).
- Sprint 7 fix round 1 (D3, FR1): BUG-T3-S7-07: `ci-policy.sh` gained the rules the first review found missing, each with a mutation that turns it red (`tests/scripts/ci-policy-mutations.sh`, 84 checks: a control run and 83 single mutations of the workflows and release scripts): no `cargo install --path` or any other install from the
  checkout in `release-rehearsal` or `publish.yml`; no `${{ }}` in any `publish.yml` `run:` step and no `${{ matrix.* }}` in any `run:` step of any workflow; the PyPI `packages-dir` is exactly the staging directory `pypi-dist/`, made with a plain `mkdir`, copied from `lists/pypi.txt`, count-checked, and the step right before the action;
  `timeout-minutes` on both publish jobs (75 and 30, pagetriage's values); the `cargo-deny` job passes `matrix.checks` through step env as `CHECKS` and validates it against the two fixed values before use.
- Sprint 7 CI fix round 2 (D3), the two red jobs of CI run 44651027362 at 7c90f6b, both in test harness code (no shipped file behaves differently, except that
  `scripts/release/publish-dry-run.sh` no longer has the hazard in its own checks):
  `release-doc.sh` (job `packaging dry runs`, Ubuntu) ran `sed -n '/^## Status/,/^## Install/p' README.md | grep -qF "$VERSION"` under `set -o pipefail`. `grep -q` exits at the first match
  (byte 119 of a 9438-byte section), GNU sed writes to a pipe in 4096-byte blocks and its next write met the closed pipe (`sed: couldn't flush stdout: Broken pipe`), so the pipeline failed
  although the README names 0.1.3. GitHub Actions starts steps with SIGPIPE ignored (the producer gets EPIPE; with the default it dies with 141), and whether the producer outlives the match
  depends on buffer sizes and scheduling, which is why the Mac passed. `gq` in `tests/scripts/lib.sh` is grep without `-q` and with its output discarded; every `| grep -q` of the test scripts
  (35 sites) and the five in `scripts/release/publish-dry-run.sh` read their whole input now, and `tests/scripts/pipefail-grep-q.sh` reproduces the failure on the real README with a producer that
  outlives the match (status 141 with the default SIGPIPE, 1 with it ignored; `gq` gives 0 in both) and fails on any new `| grep -q` or `| grep -m N` in the scripts and workflows.
  `release-rehearsal (windows-latest)`, step Quick start: `quickstart.mjs` took Git Bash from `EXEPATH\bin\bash.exe`, but the runner's `shell: bash` starts `C:\Program Files\Git\bin\bash.EXE` and Git Bash
  then sets EXEPATH to `C:\Program Files\Git\bin` (`spawnSync C:\Program Files\Git\bin\bin\bash.exe ENOENT`). It now tries both spellings, then `ProgramFiles\Git`, never the System32 WSL launcher and never a bare
  `bash`. The scrubbed environment also lost `PYTHON=python` (so `scripts/package-npm.sh` would have used `python3`, which the Windows runner does not have) and the Windows system variables the linker lookup
  reads; `PYTHON` and a fixed list of those variables are kept, still with no `GITHUB_*`, `RUNNER_*` or token. Both Windows rules are checked on any host by the harness self-test (`path.win32`).
- Sprint 7 CI fix round 2 (architect): every `dtolnay/rust-toolchain` step in `ci.yml`, `publish.yml` and `pages.yml` now installs the components (`rustfmt`, `clippy`) and the target
  (`wasm32-unknown-unknown`) that `rust-toolchain.toml` lists, so no `cargo` call starts a rustup implicit install (the path that died with "detected conflict: 'bin/cargo-clippy'" in pagetriage's
  CI run 44651022212). `ci-policy.sh` check O holds all 11 steps to `rust-toolchain.toml`, and five new mutations in `ci-policy-mutations.py` turn it red.

### Security

- S1-126 (TD-123): `cargo package --workspace --locked` is run twice by every rehearsal and by the publish build and the two `.crate` files must be byte-identical (on macOS, in every local run: identical; the digests are in the rehearsal report and in `evidence/sprint-7/D3/gates-s7.log`, and they change whenever the README changes, since each crate carries it); the publish job
  compares the re-packaged digests with the signed manifest before `cargo publish`. If the two runs ever differ, the rehearsal fails and the crates must leave the signed set.
- S1-127 (R4): no key is placed in an application trust set; `docs/release-keys.json` is read only by `release-tool verify` and the publish job, and holds no key today. R1 and R2: the rehearsal shows that the test key cannot sign a `-release` id and that the test-key flag with a release id is a usage error.
- No workflow of this repository reads a secret except `publish.yml`'s two registry tokens, inside the step env of its publish job; `id-token` and `attestations` are held only by that job (and by the Pages deploy job); no workflow uses `pull_request_target` or `workflow_run`.
- Dependabot: 0 open updates for this repository on 20 Nov 2026 (read with `gh`); the lockfile changed only by the four package version lines.
- Sprint 7 fix round 1 (D3, FR1): BUG-S1-S7-03 / S1-131: the job that holds the registry tokens compiles nothing. `publish.yml` packages and publishes the crates with `cargo package --workspace --locked --no-verify` and `cargo publish --workspace --locked --no-verify`; the re-package and the digest comparison against the signed manifest are one step with no
  token, the very next step publishes (nothing between them), both come before the third-party PyPI action (the order is now npm, the crates, PyPI), and a last step, `publish-guard.sh crate-index`, reads crates.io's sparse index until both crates show the signed sha256 (it asks again for up to 10 minutes on a 404, a server error or a missing line, and fails at once on a different
  checksum, a yanked entry, two lines or a malformed one). `scripts/release/build-artefacts.sh` packages twice with the build check and twice with `--no-verify` and fails unless all four give the same bytes (on macOS: identical, the digests are in the rehearsal log), so the digest the publish job compares is the one that was signed; `publish-dry-run.sh` runs the workflow's command with `--dry-run`.
  `tests/scripts/publish-guard.sh` grew to 117 checks (the index check with stand-ins for `curl` and `sleep`), and rules M of `ci-policy.sh` pin the order and the flags, each with a mutation.
- Sprint 7 fix round 1 (D3, FR1): TD-125: no `vars.` in any job-level `if` (an environment's variables are not visible there); the armed check is step 2 of the publish job, right after the checkout, and `RELEASE_KEY_ID` is step 3; both variables are read once each, in step env of the publish job; `docs/RELEASING.md` sets both with `--env release` and arms just before the approval.
- Sprint 7 fix round 1 (D3, FR1): S1-135: `docs/RELEASING.md` step 11 tells the owner to compare the npm tarball, the sdist and the two crates with an independent build of the same commit (the push run's `REHEARSAL-test-key-NOT-A-RELEASE-glyphsift-ubuntu-latest-<sha>` artefact, or a local `scripts/release/rehearse.sh` with the pinned tools) before signing, and says that wheels compare only between the two CI builds.

### Deferred

- A real signing key, the reserved names, the `release` environment, its variables and secrets, the tag and the publish: the owner's (`docs/RELEASING.md`). npm trusted publishing (it needs npm 11.5.1 or later, TD-122) is decided after the first token publish.
- The 8 GB laptop benchmark (not measured on 8 GB) and everything that needs it; scripts other than Devanagari (TD-80); OCR (TD-72).
- The three-operating-system proof of the rehearsal, the Windows junction case and the Windows install checks: only the owner's push can show them (`docs/release.md`, "Sprint 7: what only CI can prove").

## [0.1.2] - 2026-11-19 (untagged)

Sprint 6 (19 Nov 2026, untagged), glyphsift **0.1.2** (TD-69). 0.1.0 and 0.1.1 were never tagged; 0.1.2 supersedes them. Nothing is published, signed or tagged. The scoring, the weights, the
report spec (`glyphsift.report/0.2`), the gate rules and the benchmark CSV and SVG did not change: `bench --verify` passes and the reports are byte-identical.

### Added

- `docs/what-glyphsift-measures.md` (D3-03): a short page on what the score is, built only from committed files: the benchmark CSV (420 rows; 0 of 60 series rise as noise rises), the gate
  threshold (975000 ppm, with the gap it sits in), and the byte-identical native, Python and WASM results on 13 samples and 200 gate cases. Every number cites its file and command, and
  `tests/docs_numbers.py` (run by `tests/scripts/docs-numbers.sh`) re-reads each one from its file and fails if a cited CSV value is changed. Its limits: Devanagari only, unpublished, synthetic text only,
  no claim about Hindi answer quality, not measured on 8 GB. The demo build serves it as `what-glyphsift-measures.txt` and the footer links it.
- `tests/scripts/cargo-target-dir.sh` (BUG-T2-S5-14): proves, in a scratch checkout with no `target/`, that the native gate leg and `scripts/build-wasm.sh` work with `CARGO_TARGET_DIR` set (absolute and relative).

- S1-106 and COM0/LPT0 (T2-NOTE-COM0): `scripts/lib/confine.mjs` ports pagetriage's output-containment change (Windows device names including `COM0` and `LPT0`, doubled and `path.win32` forms) with the same case list (`tests/scripts/confine.test.mjs`, 43 tests). Proven on a model; real NTFS after the push.

### Changed

- Version 0.1.2 everywhere (workspace, crates, `Cargo.lock`, wheel, npm package).
- Demo: a Sprint 6 status line, a footer link to the measures page and two lines in the "What this demo does not do yet" box; no CSP change.

### Fixed

- BUG-T2-S6-06: `scripts/package-npm.sh` honours `CARGO_TARGET_DIR` (new section in `tests/scripts/cargo-target-dir.sh`).
- BUG-T3-S6-02: banned-word cleanup in `tests/docs_numbers.py` (clean-room wording rule).
- BUG-T3-S6-R2-08: `docs/release.md` quotes the wheel size in KiB, since exact wheel bytes vary with the checkout path.
- S1-118, BUG-T2-S5-15 and BUG-T2-S5-16: the sdist shipped `crates/glyphsift-core/tests/corrupt.rs` and `gate_noise.rs` (`required-features = ["corrupt"]`), which `cargo test` skipped silently, and
  `corrupt.rs` fails when run because `docs/corruption-generator.md` was not shipped. `scripts/add-sdist-files.py` now adds that file (four repository-root files in all) and
  `tests/scripts/sdist-locked.sh` runs `cargo test --locked --no-fail-fast -p glyphsift-core --features corrupt` from the unpacked sdist and requires both test binaries to have run with at least one test passed
  (28 and 3 tests). The CLI's own corrupt test (`crates/glyphsift-cli/tests/corrupt.rs`) is not in the sdist, because maturin ships only `glyphsift-core` and `glyphsift-py`; the test asserts that too.
- BUG-T2-S5-14 and BUG-T2-S5-16: `tests/determinism/run_gate_native.mjs` (the native determinism leg), `tests/demo/check_demo.mjs` and `scripts/build-wasm.sh` looked in a literal `target/`; they now use
  `${CARGO_TARGET_DIR:-target}`, so with the variable set the leg tests the binary the script just built instead of a stale one. The gate script prints `cli: <path>` so the binary used is visible.
- `docs/release.md` row 6 cites the log that contains the sdist's `cargo test` run (`evidence/sprint-6/D3/gates-s6.log`), not a log without one.
- Carried from Sprint 5, fixed after its wrap-up (CI run 44325740893, wheel tag check): the wheel contents check compared tags as strings and failed on the Linux wheel only (CI run 44325740893 at b3ea291: `wheel and sdist (ubuntu-latest)`, one failure, `WHEEL records the same
  platform tag as the filename`; the macOS and Windows legs were green). A manylinux wheel's filename carries a compressed tag set (PEP 425), `cp39-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64`, and
  its `WHEEL` file one `Tag:` line per expanded tag (`Tag: cp39-abi3-manylinux2014_x86_64`, `Tag: cp39-abi3-manylinux_2_17_x86_64`, as maturin 1.16.0 wrote them in the Linux wheel of run 43667702791),
  so the literal `Tag: cp39-abi3-<compressed name>` the check searched for is never there. `tests/python/check_wheel.py` now expands the filename's tag set (cross product of the dot-separated python, abi and
  platform parts) and the `Tag` headers of `WHEEL` and requires the two sets to be equal: no tag missing, none extra, line order irrelevant. It is not a substring match: the old test also passed a
  `WHEEL` with an extra `Tag:` line, a longer platform that begins like the filename's, and the tag text inside another header (`X-Tag:`, or a `Tag:` inside a header's value); the new one rejects all four, and prints the difference when it fails.
  The check also takes the file name with `os.path.basename`, so a Windows path with backslashes parses.
- Tests first (red log, then green): `tests/python/test_check_wheel.py` (25 tests: synthetic wheels with a macOS, a `win_amd64` and a compressed manylinux name and the real `WHEEL` texts, run through the real
  script, plus the cases that must still fail, and direct tests of `expand_tags`, `wheel_file_tags` and `tag_mismatch`), run by `tests/scripts/check-wheel-tags.sh`, so by `tests/scripts/run-all.sh` and the
  `packaging` job. Against the old script the three compressed-name cases (the manylinux name, a reordered `WHEEL` and a CRLF `WHEEL`) and the four loose-match cases fail on macOS, which is how the Linux-only fault is reproduced without a Linux wheel.

### Security

- The determinism evidence can no longer pass on a stale binary when `CARGO_TARGET_DIR` is set (S1-118 part a), and the sdist's shipped tests now run (part b). No third-party code or dependency changed.

## [0.1.1] - 2026-11-18 (untagged)

Sprint 5 (18 Nov 2026, untagged), glyphsift **0.1.1**: the gate call (TD-42), the sdist fix (S1-103), the first CI read of the `wheels` job and
the version bump (TD-43). 0.1.0 was never tagged; 0.1.1 supersedes it. Nothing is published, signed or tagged. The scoring, the weights, the report spec (`glyphsift.report/0.2`) and the
benchmark CSV and SVG did not change: `bench --verify` passes and the reports are byte-identical.

### Added

- The gate call, `gate(text, threshold_ppm)` (D3-01, TD-42): for one chunk of extracted text it answers `pass`, `hold` (a Devanagari chunk whose score is below the
  threshold) or `not_scored` (text that is not mostly Devanagari is passed through unjudged), as the canonical JSON `glyphsift.gate/0.1`
  `{spec, scored, script, devanagari_ppm, ppm, threshold_ppm, verdict}`. Letters are `char::is_alphabetic()` plus the blocks U+0900..U+097F, U+A8E0..U+A8FF and U+1CD0..U+1CFF;
  `devanagari_ppm` is the floored share of block letters; no letters is script `none`, under 500,000 ppm is `other`, both `not_scored` with `ppm` null; otherwise `ppm` is exactly
  `validate(text).score.ppm` (computed without building the per-cluster report). Rust core (`gate`, `gate_to_canonical_json`, `parse_threshold`, `GateReport`, `Error::InvalidThreshold`),
  CLI `glyphsift gate [--threshold-ppm N] FILE|-` (exit 0 for every verdict, 2 for invalid UTF-8 or a bad threshold, 1 for I/O or input over 4 MiB), Python
  `glyphsift.gate(text, threshold_ppm=None)` with `GATE_SPEC` and `DEFAULT_GATE_THRESHOLD_PPM` and type stubs, and WASM `gate(text, threshold_ppm?)`, `gate_spec()` and
  `default_gate_threshold_ppm()` (also in the npm package). An unpaired surrogate is rejected by every binding (WASM: a `TypeError` through `String.prototype.isWellFormed` before the module
  is called, because wasm-bindgen would turn it into U+FFFD; Python: `ValueError`; CLI: exit 2); a threshold outside 0..1000000 is a `RangeError` (WASM), `ValueError` (Python, core), exit 2 (CLI), and a non-integer one a `TypeError`.
- `DEFAULT_GATE_THRESHOLD_PPM`, 975000, derived from `docs/score-vs-noise.csv` in the new [docs/gate.md](docs/gate.md): it sits in the gap between the `mixed` family at p=0.1 (lowest seed 982,847) and at
  p=0.2 (highest seed 970,520). The doc also says what a hold means for a reader and which noise produces one (`control_leak` at p=0.1 or `virama_insert` at p=0.2 hold 285 and 287 of 288 three-line chunks; `mixed` at p=0.4 holds 274, so a fixture must be checked),
  with the exact hold counts pinned by `crates/glyphsift-core/tests/gate_noise.rs`.
- Tests first (red logs before green): `crates/glyphsift-core/tests/gate.rs` (the boundaries at 499,999 and 500,000 ppm, threshold equality, the canonical bytes, 4 MiB, 10,000 seeded random strings with combining marks, block edges and the 4 MiB boundary and no panic, and a re-derivation of the default threshold from the committed CSV),
  a gate fuzz hash over 40,000 probes shared by native and WASM (`GATE_FUZZ_HASH`), `crates/glyphsift-cli/tests/gate.rs`, and `tests/determinism/gate/`: 200 synthetic cases (`scripts/make-gate-corpus.mjs`,
  six ill-formed and one over 4 MiB) whose recorded answers native (`run_gate_native.mjs`), Python (`run_gate_python.py`) and WASM (`run_gate_wasm.mjs`) must reproduce byte for byte or reject, wired into `scripts/determinism.sh`.
- The demo's Gate tab (D3-04): Report and Gate tabs under the text input; the Gate tab shows the verdict, the Devanagari share, the score, a threshold field (975000 by default, whole numbers 0 to 1,000,000)
  and the canonical JSON, all as text nodes; an unpaired surrogate, a bad threshold and a refused file show plain-text messages and leave no stale verdict. `tests/demo/check_demo.mjs` now makes 234 checks (150 in CI at 5ff0c47).
- `scripts/package-sdist.sh` and `scripts/prune-sdist-lock.py` (S1-103, D3-02): the sdist is built with maturin, its `Cargo.lock` is pruned to the packages its own workspace reaches
  (61 entries to 36, same versions and checksums) and the unpacked sdist is built `cargo build --locked`. Tests: `tests/scripts/sdist-locked.sh`.
- `tests/scripts/release-doc.sh` (BUG-T3-S4-24, D3-03): row 6 of `docs/release.md` cites exactly one `gates-*.log`; the first CI run of the `wheels` job is recorded; one version everywhere.
- A `doc` CI job, `RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked` (BUG-T2-S4-22), and a wheel contents check (`tests/python/check_wheel.py`) on every platform's wheel in the `wheels` job.
- `scripts/throughput.mjs` also times `gate()` and `glyphsift gate`: WASM `gate()` takes 40 ms on the 1 MiB corpus against 234 ms for `validate()` (Apple M5 Pro, 48 GB; not measured on 8 GB; `evidence/sprint-5/D3/green/throughput.log`, which records no commit: raw data not kept; superseded on 20 Nov 2026 by `docs/benchmarks/throughput-m5pro-48gb.json`).

- Fix round 1 (TD-53, BUG-T2-S5-02 / T3-S5-02 / S1-111): `scripts/lib/confine.mjs`, pagetriage's output-path confinement ported unchanged apart from its header, with
  `tests/scripts/confine.test.mjs` (36 tests: the Windows rules through `path.win32` and an in-memory volume, real symlinks and hard links, a real junction on Windows; none skipped) and
  `tests/scripts/release-manifest.sh` rewritten (68 checks: `MSYS=winsymlinks:nativestrict`, `[ -L ]` after every link, a junction made with MSYS argument conversion off, hard-link,
  symlink-to-a-file-in-`dist/`, case-spelling and one-line-error cases). The `check` job runs both on ubuntu, macOS and Windows (setup-node, same pinned action as the other jobs).
- `tests/scripts/readme-claims.sh` (BUG-T1-S5-05, T3-S5-03, T3-S5-15): the README's first Status line is the status line verbatim and equals the demo's, every 8 GB cell reads
  "not measured on 8 GB", and the throughput figures in the README and here equal the log they cite. `tests/scripts/ci-policy.sh` sections I (the containment step) and J (`cargo doc` prints no
  "collision"), and `tests/scripts/release-doc.sh` sections D (packaging notes) and E (output confinement), are new.
- `docs/release.md`: "Packaging notes" (a local macOS wheel is not byte-reproducible across checkout paths, only CI-built wheels are signed and published; the sdist is a source release that
  includes `crates/*/tests` on purpose, TD-56), "Output confinement of `release-manifest.mjs`", and the owner's push-list line "glyphsift check (windows-latest) proves the ported containment".

### Changed

- The workspace, every crate, `Cargo.lock`, the wheel and the npm package are version 0.1.1 (TD-43).
- `docs/release.md` records the first CI run of the `wheels` job: run 43667702791 at 5ff0c47, read with `gh` on 18 Nov 2026, built a `manylinux_2_17` wheel (254,335 bytes), a `win_amd64` wheel (151,328), a macOS arm64
  wheel (247,045) and an sdist (82,081) (these sizes are committed in `docs/benchmarks/ci-run-43667702791.json`), all green on 14 of 14 jobs, with what it did and did not prove. READMEs, the demo's not-yet box and the release checklist no longer say the Linux and Windows wheels are built only after the owner's push.
- The CI `wheels` job builds its sdist with `scripts/package-sdist.sh`; the `packaging` job gives the script tests the hashed maturin (`GLYPHSIFT_TOOLS_VENV`).
- `docs/RELEASING.md` no longer copies the `packaging` job (the copy had gone stale); it points at `ci.yml`.
- The root README no longer contains the literal builder-path prefixes the artifact checks search for (the sdist ships a copy of it as the core crate's README).

- `scripts/release-manifest.mjs` takes its output path through `confineOutput` and `writeConfined` (a temporary file opened with `wx` and renamed over the target) instead of a `startsWith` check and
  `writeFileSync`; it is again identical to pagetriage's script except the id and the licence constants. Exit codes are unchanged: 2 for every refusal, 1 for a write error, now one line and no stack trace.
- The README's Status section starts with the exact Sprint 5 status line (the narrative follows it); the throughput figures were corrected to the log (gate 40 ms, validate 234, score_ppm 80, check 67; that log records no commit: raw data not kept, superseded by `docs/benchmarks/`) and
  the 8 GB column of every benchmark table reads "not measured on 8 GB".
- The `glyphsift-cli` `[[bin]]` is `doc = false`: `cargo doc --workspace --no-deps --locked` documents `glyphsift-core`, `glyphsift-py` and `glyphsift-wasm` and no longer warns "output filename collision".

### Fixed

- Fix round 2 (BUG-T2-S5-12, BUG-T2-S5-14, T3-R1-03): the sdist ships `bench/corpus/clean.txt`, `docs/gate.md` and `docs/score-vs-noise.csv` (synthetic, own-authored; `scripts/add-sdist-files.py`) so `cargo test --locked` passes from the unpacked sdist, now checked by `tests/scripts/sdist-locked.sh` (an sdist of 110,435 bytes: a build fact read from that build, raw data not kept); `tests/determinism/run_gate_native.mjs` exits 1 with `cannot run <cli path>: <error>` when the CLI cannot be run instead of throwing a TypeError (`tests/scripts/gate-native-error.sh`); `docs/release.md` row 2 quotes "not measured on 8 GB".

- S1-103 / BUG-T2-S4-21: the sdist could not build `--locked` from its own `Cargo.lock` (see Added).
- BUG-T3-S4-24: `docs/release.md` row 6 cited a superseded log next to the current one (fixed at 5ff0c47, now pinned by a test).

- BUG-T2-S5-02 / T3-S5-02 / S1-111: `release-manifest.mjs` refused a differently-cased `DIST/` that is the same directory, accepted a symlink to a file inside `dist/` and wrote through it, wrote through a
  hard link to a file outside `dist/`, and printed a stack trace when `--out` used a file as a directory or a name too long (reproduced by T2 on macOS; red logs `D3-FIX1-02-*`).
- BUG-T2-S5-08: `cargo doc` warned "output filename collision" between the `glyphsift-py` library and the `glyphsift` binary, so one crate's docs overwrote the other's.
- T3-S5-03 and T3-S5-15: README and CHANGELOG throughput figures differed from the log they cite (39 / 230 / 79 / 66 against 40 / 234 / 80 / 67; raw data not kept for both sets); the 8 GB column said only "not measured".
- BUG-T1-S5-05 / T3-S5-04: the README did not start with the status line the demo and `site/data/demos.json` carry.
- BUG-T2-S5-07 and T3-S5-05 are documented, not changed (see Added: "Packaging notes").

### Security

- The gate adds no network access, storage or dependency. It is capped at 4 MiB like `validate`, allocates in proportion to one cluster rather than to the input, and refuses a string with an unpaired surrogate
  rather than silently rewriting it. 10,000 random strings and the 4 MiB boundary cause no panic.
- The release-manifest tool can no longer be pointed through a link: a symlink or junction at `--out`, even to a file inside `dist/`, a symlink or junction on the way, a dangling link, a FIFO or a
  directory is refused (exit 2) before anything is written, and a hard link inside `dist/` to a file elsewhere has its name replaced, not its bytes written through. Not closed: a process that can already
  write inside `dist/` can swap a directory for a link between the last check and the rename (documented in `docs/release.md`). The Windows rules are proven here against `path.win32` and an in-memory
  volume, and on Windows itself only by CI after the owner's push.

## [0.1.0] - UNRELEASED (release candidate, never tagged; superseded by 0.1.1)

The first release candidate: everything below, from Sprint 1 to Sprint 4. Nothing is published, signed or tagged;
the owner's open steps are in [docs/release.md](docs/release.md). Sprint 4 entries (14 Nov 2026, untagged, D3-01 to
D3-04) come first in each section, then Sprint 3. The scoring, the weights, the benchmark CSV and the WASM module did
not change in Sprint 4.

### Added

- A static `#sprint-status` line on the demo page (T1-S4-R1-05), asserted exactly by `tests/demo/check_demo.mjs`; no script, no CSP change.
- `tests/scripts/notice-mit-crates.sh` (BUG-T3-S4-18): every MIT-only crate in the cli, py, wasm and core trees has a block and the full MIT text in NOTICE.
- A `wheels` CI job: a Linux wheel (`manylinux_2_17` through zig) and an sdist on Ubuntu, a `win_amd64` wheel on Windows
  and a macOS arm64 wheel, each installed into a fresh venv with `--no-index` and checked with one real call
  (`ppm 1000000`), kept as a workflow artifact for 7 days (`retention-days: 7`, `if-no-files-found: error`). It
  publishes nothing and uses no secret, no release or registry step, and runs with `contents: read`. Configured, not
  yet run: only CI after the owner's push proves it (docs/release.md, "CI-only proofs"). D3-02
- Hashed, binary-only tool installs (S1-079): `tools/ci/requirements.in` pins uv 0.13.1, maturin 1.16.0, mypy 2.4.1 and
  ziglang 0.16.0, and `tools/ci/requirements.txt` (362 hashes, every transitive package included, generated with
  `uv pip compile --universal --generate-hashes`) is installed with `pip install --require-hashes --no-deps
  --only-binary=:all:`; Playwright 1.65.0 comes from the committed `tools/playwright/package-lock.json` with
  `npm ci --ignore-scripts` (every entry has an `integrity` hash). `scripts/package-python.sh` uses the hashed venv when
  `GLYPHSIFT_TOOLS_VENV` is set and reads its version pins from `tools/ci/requirements.in`. D3-02
- Script tests: `tests/scripts/run-all.sh`, `package-npm-default-scratch.sh` (BUG-T2-S3-19-R2), `lockfile-integrity.sh`
  (lockfile and hashed requirements, with negative cases) and `ci-policy.sh` (every `uses:` is a SHA row of the
  conventions table; no `pip install uv==`, `uvx` or `npm i` in `packaging`, `demo-browser` or `wheels`; `--locked` on
  every cargo and maturin build; the `upload-artifact` and no-publish rules). D3-01, D3-02
- `docs/v0.2-tamil.md`: a design note, no code, for Tamil as the v0.2 second script (Bengali later): what carries over from
  the sixteen Devanagari rules, the two-part vowels, the visible pulli, legacy encodings, the test table and generator
  plan, with a probe of what v0.1 does with Tamil text today. Design only; not implemented. D3-04
- The demo's third-party notices are served as `NOTICE.txt` and the footer links it; the not-yet box says "Tamil planned
  for v0.2, Bengali later" and that Linux and Windows wheels are built only by CI after the owner's push.
  `tests/demo/check_demo.mjs` now makes 148 checks (145 after the NOTICE change, three for the new box wording). D3-03, D3-04

- Python wheel packaging: type stubs `glyphsift.pyi` (installed as `glyphsift/__init__.pyi`) and `py.typed`, the
  `Development Status :: 3 - Alpha` and `Typing :: Typed` classifiers, and a wheel README with the "Not published
  yet" sentence, the platform tag proven (`macosx_11_0_arm64`) and "Linux and Windows wheels are not built yet".
  `scripts/package-python.sh` builds with `uvx maturin`, inspects the wheel (`tests/python/check_wheel.py`),
  installs it into a `python3 -m venv` with `pip install --no-index --no-deps` and into a `uv venv` with
  `uv pip install --offline --no-index --no-deps`, runs a real call in each, and runs `mypy --strict` on a script
  that uses the stubs. D3-04
- npm package `@airplanemode/glyphsift` 0.1.0 from the wasm-bindgen output: `scripts/package-npm.sh` (package.json
  with no scripts, dependencies, bin or `type`; `node`, `import` and default exports; `sideEffects: false`),
  `npm/README.md`, `npm pack` into `dist/npm`, an offline install into a fresh empty directory with an empty
  cache, `npm ls` showing one package, and a Node call byte-equal to `glyphsift check`
  (`tests/npm/check_node.mjs`); a bundler-free page in installed Chrome (`tests/npm/index.html`,
  `tests/npm/check_browser.mjs`). D3-05
- CLI surface tests: `--version` is 0.1.0, `--help` names every command and exit code, a directory is exit 1, the
  README `### CLI` section documents the commands and all four exit codes, every crate ships `LICENSE` and `NOTICE`,
  the README tables have the 8 GB column reading "not measured", and no README cites a scratch path. The CLI,
  core and WASM crates now carry copies of `LICENSE` and `NOTICE`, as the Python crate did. D3-06
- Demo: a per-cluster heatmap (one row per line with a strip, a span per cluster, buckets from the sum of the
  weights of the rules that fired, a legend, capped at 20,000 clusters with a note), drag and drop and a file
  picker for a local `.txt` file (size checked before the file is read, fatal UTF-8 decoding, BOM and CRLF kept,
  refusals in plain text, no request), invisible tag characters shown as `<U+XXXX>`, and a source gate against any
  style attribute. `tests/demo/check_demo.mjs` now makes 138 checks (adding the heatmap against the report for all five
  samples, drop and picker against `glyphsift check FILE` and paste, zero requests, the refusals, the source grep)
  and screenshots; fixtures in `tests/demo/fixtures`. D3-07
- `docs/release.md` (the seven definition-of-done rows, each with a status, evidence, owner and
  blocker-for-tag, and an "Owner must" block with commands) and `docs/RELEASING.md`. D3-08, D3-09
- `scripts/release-manifest.mjs`: an unsigned `airplanemode.manifest/0.1` for the wheel and the npm tarball
  (id `glyphsift-release`, licence Apache-2.0, version from `Cargo.toml`, `SOURCE_DATE_EPOCH` 0 to 253402300799,
  output confined to `dist/`, no signing option and no key read); identical to pagetriage's script except two
  constants. `tests/scripts/release-manifest.sh` (42 checks). A dry run with the public RFC 8032 test key
  through `cp-sign` verified with `--allow-test-key` and was refused without it; nothing signed is in the repository.
  D3-09
- CI: a `packaging` job (the wheel, the npm tarball and the release-manifest tests) and a `demo-browser` job (the
  demo and npm browser checks in the runner's Chrome), both on Linux only; configured, not yet run. D3-04, D3-05, D3-07
- Seven `known_gap_*` table cases (147 to 154) that pin what still scores clean: U+200B, U+2060, U+00AD, U+2062,
  U+1F3FB and the halfwidth marks U+FF9E and U+FF9F after a Devanagari base. No rule, weight or the bench CSV changed; the
  rule count is still 16 and the report spec glyphsift.report/0.2. BUG-T2-S3-01
- `scripts/remap-paths.sh` (`--remap-path-prefix` for the cargo, rustup and checkout directories, appended to any
  existing RUSTFLAGS), `scripts/check-no-builder-paths.py` (fails if a wheel, tarball or binary contains `/Users/`,
  `/home/` or `/private/tmp`) wired into `scripts/package-python.sh` and `scripts/package-npm.sh`, and a CLI
  install step in the CI `packaging` job. BUG-T2-S3-02, T3-S3-007
- `scripts/throughput.mjs`, the throughput measurement behind README Benchmarks (paths from its location and arguments). T3-S3-013
- Table cases for BUG-T2-S2-07 and BUG-T2-S2-15: 54 new cases (93 to 147), 32 of which failed before the rule change
  (`red-D3-01.log`, `red-D3-02.log`); two determinism samples (`12-joiners-emoji-persian`,
  `13-tags-and-foreign-marks`, 13 in all) that must be byte-identical on native, Python and WASM; the fuzz alphabet
  gains two emoji, a variation selector, two foreign marks and three tag characters. D3-01, D3-02

- `validate()`: the Devanagari validator. Sorted `const` code-point tables, a cluster grammar parsed
  once per cluster in linear time, and the sixteen rules, each a small predicate; all 93 cases of
  `tests/cases/devanagari.toml` pass (the 77 Sprint 1 cases plus CRLF, a lone CR, a BOM at offset 0 and
  after a BOM, a 2,000-matra run and edge cases the first table left open). The harness is no longer
  `#[ignore]`d. D3-01
- No-panic fuzz test: 20,000 xorshift64* strings (seed 1) over `U+0000..U+097F`, ZWJ, ZWNJ and private
  use code points; issues in order, every issue naming a code point of its own cluster; the FNV-1a hash
  of all 20,000 canonical reports is pinned and asserted again over the WASM build. D3-01, D3-05
- `unicode-general-category` 1.1.0 (Apache-2.0, no dependencies, Unicode 16.0 tables) in the core:
  unassigned code points, letters of other scripts and Indic combining marks of other blocks. D3-01
- Report `glyphsift.report/0.2`: `summary.by_kind`, `lines` (per-line index, byte and cluster ranges,
  flagged clusters and score) and `score` (`ppm`, `penalty`, and the `weights` used). A CRLF cluster ends
  its line and is never flagged. D3-02
- Integer score in parts per million, `1_000_000 - floor(penalty * 1000 / cluster_count)`, penalty being the
  largest weight per flagged cluster, summed; weights are one integer in 1 to 1000 per rule in
  `crates/glyphsift-core/weights/devanagari.toml`, every line with a `# source:` comment, read by a strict
  parser that refuses a missing, duplicate, unknown or out-of-range entry. D3-02
- `glyphsift-core::corrupt` behind the non-default `corrupt` feature: the seeded, counter-based OCR-corruption
  generator for all 19 families of `docs/corruption-generator.md` plus `mixed`; a corrupted site at one `p` is
  corrupted identically at every larger `p` and the site sets are nested. The WASM and Python builds do not
  carry it. D3-03
- `bench/corpus/clean.txt`: 288 invented Hindi and Marathi lines, every one validating with zero issues. D3-03
- CLI `glyphsift corrupt --family <f>|mixed --p <decimal> --seed <u64> [--sites <path>]` and `--list-families`;
  exit 2 on bad arguments. D3-03
- CLI `glyphsift bench`: the score-versus-noise benchmark over the schedule p in {0, 0.01, 0.02, 0.05, 0.1, 0.2,
  0.4}, every family and `mixed`, seeds 1 to 3; writes `docs/score-vs-noise.csv` and a deterministic, inert
  `docs/score-vs-noise.svg`, and exits 1 on any violation of the criterion (mixed mean strictly falling,
  mixed and every triggering family non-increasing per seed, 1_000_000 at p=0). `bench --verify <csv>`
  re-checks an existing CSV. The chart is embedded in the README with the reproduce command. D3-04
- CLI `glyphsift check FILE|- [--fail-under <ppm>]`. D3-05
- WASM exports `score_ppm(text)` and `report_spec()` of `glyphsift.report/0.2`; `tests/wasm/run_wasm_safety.mjs`
  runs the fuzz set, a 1 MiB input, a 1 MiB single-cluster run and an over-limit input with no trap, asserts the
  export list, and logs the 5,000-mark to 2,500-mark time ratio (1.99). D3-05
- Python `glyphsift.score_ppm(text)`. D3-08
- `scripts/determinism.sh` and `tests/determinism/{samples,expected,run_python.py,run_wasm.mjs}`: eleven synthetic
  samples (CRLF, bare CR, BOM, controls, joiners, a mark run, empty) whose reports must be byte-identical on the
  native CLI, the Python wheel and the WASM build; a `determinism` CI job on Linux, macOS and Windows (Windows
  configured, not yet executed). D3-08
- CI `deny` job: cargo-deny 0.20.2 as a Linux release binary checked against a pinned SHA-256 (no Docker action),
  advisories leg `continue-on-error`; `deny.toml` reconciled with the licence allow-list
  (`Apache-2.0 WITH LLVM-exception` added for `target-lexicon`, reached through PyO3), `wildcards`, unknown
  registry and unknown git all denied, yanked crates denied. D3-06
- CI steps: WASM binding unit tests, `bench --verify` of the committed CSV, a check that the `corrupt`
  feature is absent from the WASM build, and the float and hash-collection scan of the core sources. D3-06
- Demo: the real report for pasted text and five synthetic samples (adds an adversarial one, and splits the
  legacy-font sample into "read as Latin", which scores 1.0000, and "residue"): the document score, a per-line
  table with per-line scores and issues, the sixteen rules with weights and counts, the clusters, and the
  canonical JSON, byte-identical to the CLI. Pasted input over 1 MiB of UTF-8 is refused before the WASM module
  is called. `scripts/check-demo-sources.sh` fails the build on `innerHTML`, `outerHTML`, `insertAdjacentHTML`,
  `eval` or inline script, style or handler. `tests/demo/check_demo.mjs` drives the built demo in Chrome under
  `/glyphsift/`. D3-07
- GitHub Pages demo at <https://airplanemode-labs.github.io/glyphsift/> (`demo/`, assembled by
  `scripts/build-demo.sh`, deployed by `.github/workflows/pages.yml`, built again by the CI `demo`
  job), with a "What this demo does not do yet" box (what it shows now is under Sprint 2 above). D3-07
- WASM exports `clusters_json()`, `issue_kinds()` and `report_spec()` next to `validate()` and
  `clusters()`; the wasm crate uses the workspace `serde_json` (no `preserve_order`) instead of a
  hand-rolled array serialiser. D3-05
- `scripts/install-wasm-tools.sh`: installs wasm-bindgen 0.2.129 and binaryen 133 from official
  release tarballs, comparing each against a SHA-256 digest pinned in the script.
- `persist-credentials: false` on every `actions/checkout` in CI.
- Cargo workspace (resolver 3) with `glyphsift-core`, `glyphsift-cli`, `glyphsift-py` (PyO3 0.30,
  abi3-py39, maturin) and `glyphsift-wasm` (wasm-bindgen 0.2.129); rust-toolchain 1.98, edition 2024.
- Report types `Report`, `Cluster`, `Issue`, `IssueKind` (sixteen Devanagari rules) with the
  canonical compact-JSON rule.
- `clusters()`: UAX #29 extended grapheme clusters with byte offsets (unicode-segmentation 1.13).
- Tests-first case table `crates/glyphsift-core/tests/cases/devanagari.toml` (77 cases at the time,
  93 now) with checks that the table parses, covers every `IssueKind` and matches the segmenter.
- `docs/devanagari-rules.md` (code-point tables, cluster grammar, rule definitions, public API) and
  `docs/corruption-generator.md` (noise families, schedule, evaluation protocol, CLI shape).
- `deny.toml` licence policy, `clippy.toml` determinism rules (no HashMap/HashSet, no platform libm),
  `scripts/build-wasm.sh`.
- CI on ubuntu, macos and windows: fmt, clippy, test, wasm32 checks, PyO3 check, licence sweep;
  actions pinned by SHA; Dependabot for cargo and github-actions.
- LICENSE (Apache-2.0), NOTICE, README with Limitations, CONTRIBUTING, SECURITY.

### Changed

- Every cargo and maturin build, test, check, run and install line in `ci.yml` and in the build scripts says `--locked`
  (`maturin sdist` has no such flag; the `wheels` job checks that `Cargo.lock` is unchanged after it). The `packaging`
  job installs its tools by hash and runs the script tests; the `demo-browser` job installs Playwright with `npm ci`
  from the lockfile instead of `npm i`. `scripts/determinism.sh` pins `maturin==1.16.0` (by version, a known gap: not
  by hash). D3-02
- The README says Sprint 4, names the benchmark machine "Apple M5 Pro, 48 GB" and says "not measured on 8 GB"; the
  Linux and Windows wheels are described as built only by CI after the owner's push, no longer as a Sprint 4
  carry-over. The wheel README says the same. NOTICE names the author of the MIT-only crate zmij (David Tolnay, from
  its Cargo.toml: its licence file has no copyright line). D3-03, D3-04
- `docs/release.md` records what Sprint 4 closed and lists what only CI can prove and the known gaps in the hashed
  installs (the pip that `setup-python` ships is unpinned; `determinism.sh` installs maturin by version only). D3-04

- NOTICE lists every third-party crate compiled into the wheel, the WASM and the CLI with its licence (derived from
  `cargo tree -e normal` and `cargo metadata`), names the compiled Unicode tables (`unicode-general-category`
  1.1.0, Apache-2.0; `unicode-segmentation`) and no longer says no Unicode data is redistributed. The wheel's OS
  classifier is `Operating System :: MacOS`. The wheel carries no SBOM (maturin's Rust SBOM embedded the builder's path). T3-S3-014
- `scripts/package-python.sh` pins `uvx maturin@1.16.0` and `uvx mypy@2.4.1` and prints both versions. T3-S3-011
- `docs/release.md`: each Open row begins with an `Owner must:` line; the registry install commands sit in a block headed
  "After the owner publishes"; the full `check_demo.mjs` command is given. T3-S3-011, T3-S3-013
- README Limitations and `docs/devanagari-rules.md` section 7 state the invisible-text gap, the lone-surrogate behaviour of each
  runtime (Python `UnicodeEncodeError`, WASM U+FFFD, CLI exit 1) and that identical results mean valid Unicode text; the `.pyi`
  docstrings say the same. BUG-T2-S3-01, BUG-T2-S3-10
- README score tables gain the 8 GB column, reading "not applicable (deterministic score)". T3-S3-014

- `zwj_zwnj_misplaced` fires only when the code point is a ZWJ or ZWNJ, the previous code point is not a virama,
  and the cluster is Devanagari-based (its first code point is Devanagari-class) or the joiner starts the cluster.
  Emoji ZWJ sequences, a Persian ZWNJ and Latin or Arabic letters with a joiner are no longer flagged; consonant
  plus ZWJ without a virama, a doubled joiner and a lone joiner still are. A joiner that joins a space's cluster is
  no longer flagged either. Same rule, same weight (200). BUG-T2-S2-07, D3-01
- Tag characters (`U+E0001`, `U+E0020` to `U+E007F`) in a Devanagari-based cluster, or starting a cluster, are
  `unexpected_code_point` (`U+E0001` is always its own cluster, so it is caught by the second condition); the England
  flag is clean. Combining marks (Mn, Mc, Me) on a Devanagari base outside Devanagari, Devanagari Extended,
  Devanagari Extended-A and Vedic Extensions, and not a joiner or variation selector, are `mixed_script_in_cluster`
  (the rule-14 class `OtherMark` now covers every foreign combining mark, not only `U+0980..U+0DFF`); `e` plus
  `U+0301` is clean. The rule count stays 16, `IssueKind::ALL` and every weight are unchanged, and `REPORT_SPEC`
  stays `glyphsift.report/0.2`. BUG-T2-S2-15, D3-02
- Because those rules changed what is flagged: `FUZZ_HASH` re-pinned (`0x3406f55bff039ed3` to `0x9f8eceb1f973730b`) in
  the fuzz test and in the WASM safety script; the expected report of determinism sample 07 lost one issue (a ZWNJ
  after a space); the `by_kind` test in `tests/score.rs` puts its ZWNJ on a consonant instead of a space; the
  generator's `joiner_inject` family still injects at every eligible boundary but declares an expected rule only
  where the joiner lands in a Devanagari-based cluster or starts its cluster. D3-01, D3-02
- Benchmark regenerated: 35 rows of `docs/score-vs-noise.csv` changed (all 18 `joiner_inject` rows and 17 `mixed` rows
  with p above 0), the SVG with them, and the README tables were rebuilt from the CSV (`d20efc20...` to
  `cac89041...`). Weights and corpus unchanged (SHA-256 logged before the run); two runs byte-identical; mixed mean
  still falls strictly (1.0000, 0.9985, 0.9970, 0.9917, 0.9840, 0.9675, 0.9334); mixed and all twelve triggering
  families still non-increasing per seed. D3-03
- Demo: the "What this demo does not do yet" box no longer lists the heatmap or drag and drop; it lists Devanagari
  only, structural checks only, uncalibrated weights, UTF-8 text up to 1 MiB, no service worker and nothing
  published. The adversarial sample gains a tag character, a foreign combining mark, an emoji joiner sequence and a
  Latin joiner. D3-07
- README: Status, Install (local wheel, tarball and `cargo install --path`, the "Not published yet" sentence, the
  platform tag, an "After the owner publishes" block), CLI section with the exit-code table, demo, regenerated
  benchmark tables with the 8 GB Windows column reading "not measured", and updated Limitations. `scripts/check-demo-sources.sh` also
  refuses any style attribute set from script. D3-04 to D3-08
- `validate()` returns the report instead of `Err(Unimplemented)`; `Error` is now `InputTooLarge`, returned over
  `MAX_INPUT_BYTES` (4 MiB); the `Unimplemented` variant is gone. D3-01
- `REPORT_SPEC` is `glyphsift.report/0.2` (was `/0.1`); 0.2 adds fields to 0.1 and removes none. D3-02
- CLI exit codes: 1 is an I/O or UTF-8 error (was 2), 2 is a usage error (clap's own), 4 is `--fail-under`; exit 3
  (unimplemented) is removed. D3-05
- WASM: `version()` is no longer exported; the exports are exactly `validate`, `score_ppm`, `report_spec`,
  `clusters`, `clusters_json` and `issue_kinds`. D3-05
- Python: `validate` raises `ValueError` over the limit instead of `NotImplementedError`. D3-08
- `scripts/install-wasm-tools.sh`: the Windows branch, both Windows digests (wasm-bindgen
  79e348c1..., binaryen 17a2cbea...), fail-closed digest lookup before any download and `cygpath` for
  `GITHUB_PATH`, copied from pagetriage's; it differs from pagetriage's only on the four lines that name the
  repository. D3-08
- `scripts/build-demo.sh`: the commit shown in the page comes from `GITHUB_SHA` only when it is a full 40-hex id,
  otherwise `local`; it runs `scripts/check-demo-sources.sh` first. D3-07
- `.gitattributes`: `tests/determinism/samples` and `expected` are never normalised (they contain CRLF and a
  BOM on purpose). D3-08
- Demo: the "What this demo does not do yet" box now lists no heatmap, Devanagari only, structural checks only,
  uncalibrated weights, no drag-and-drop, no service worker, nothing published. D3-07
- README: Benchmarks with the chart, the command and the criterion; Limitations name every "none directly"
  family with its curve; docs/devanagari-rules.md sections 2 to 7 describe the implementation and the score;
  docs/corruption-generator.md describes sites, coupling, the sidecar, the evaluation and the CLI as built. D3-06

### Security

- Notices (S1-090b, BUG-T3-S4-04, TD-28): the root NOTICE, its four crate copies, the npm tarball and the wheel now carry
  the full MIT text with the copyright or author line for zmij and memchr (the two compiled crates not offered under
  Apache-2.0); the sentence saying the texts are not bundled is gone. The wheel and npm checks assert the MIT text.
  The demo's NOTICE.txt is the same file. The WASM module is unchanged.

- Supply chain (S1-079): the CI jobs that build what ships install uv, maturin, mypy and ziglang by hash with
  `--only-binary=:all:` and Playwright from a lockfile with `npm ci --ignore-scripts`; every `uses:` is still a SHA row of
  the conventions table and no action was added; the `wheels` job has no publish, release or registry step.
  D3-02
- zmij attribution (TD-05): its upstream `LICENSE-MIT` (read with `gh api`, read-only) has no copyright line and equals
  the crates.io copy, so the demo's `NOTICE.txt` names David Tolnay from the crate's `Cargo.toml` and carries the full
  MIT text. D3-03

- The demo reads a local file only in the tab, checks `file.size` before reading, decodes with a fatal UTF-8
  decoder, and makes no request (0 requests during every file action in the test); a file dropped outside the drop
  zone is default-prevented so the browser does not navigate to it; no element carries a style attribute and every
  attribute is set with `setAttribute` from a fixed set. D3-07
- The wheel and the npm tarball contain no lifecycle or install script, no dependency, no source map, no test data
  and no file over 5 MB, and carry `LICENSE` and `NOTICE`; both were installed offline with scripts off. The release
  manifest tool has no signing option, never reads a key and writes only inside `dist/`. D3-04, D3-05, D3-09
- Hidden text no longer scores clean on a Devanagari letter: tag characters are flagged (`unexpected_code_point`)
  and so is any non-Indic combining mark (`mixed_script_in_cluster`). BUG-T2-S2-15, D3-02
- `scripts/build-wasm.sh` also refuses (exit 2) a `WASM_OUT` that matches `[A-Za-z]:*` (a Windows drive path) or
  contains a backslash, before cargo and before `rm -rf`; the guard is textually identical to pagetriage's
  (BUG-T2-S2-14)
- WASM `clusters()` and `clusters_json()` now return `Result<String, JsError>` and refuse input over
  `MAX_INPUT_BYTES` (4 MiB) with the same "too large" error as `validate()`; before, an 8 MiB input made
  `clusters_json` throw a string-length error and 64 MiB reached `RuntimeError: unreachable`. The export list is
  unchanged; `tests/wasm/run_wasm_safety.mjs` gains 4 MiB + 1 and 8 MiB cases for both. S1-051
- The benchmark chart is an inert SVG: integer coordinates, a fixed palette, no script, event handler, link,
  style or external reference, every text escaped; tests assert each of those. D3-04
- `validate` refuses input over 4 MiB and the CLI reads at most that much before refusing, so a crafted input
  cannot make the report grow without bound; the WASM build never traps on the 20,000-string fuzz set, a 1 MiB
  input or a 5,000-mark run. D3-01, D3-05
- The demo renders every report-derived and pasted string with `textContent` only and refuses input over 1 MiB
  before calling WASM; a grep gate fails the build on `innerHTML`, `outerHTML` and `insertAdjacentHTML`. D3-07
- The build id shown in the demo accepts `GITHUB_SHA` only when it is 40 lowercase hex digits. D3-07
- Every binary the CI downloads (cargo-deny, wasm-bindgen, binaryen, including the Windows rows) is checked
  against a SHA-256 pinned in the repository before use; no Docker action. D3-06, D3-08

### Notes

- Sprint 2 documented two known gaps for this release (joiners inside emoji and Persian text were flagged; tag
  characters and non-Indic combining marks on a Devanagari letter were not). Both are changed above (BUG-T2-S2-07,
  BUG-T2-S2-15). Remaining and documented in the README Limitations: a joiner on a space's cluster, variation
  selectors and Vedic Extensions marks on a Devanagari base, and tags after a Latin letter are not flagged.

- Weights file and corpus: the SHA-256 of `crates/glyphsift-core/weights/devanagari.toml` (`09e1d53f...`) and
  `bench/corpus/clean.txt` (`f4dba332...`) was logged before the first `glyphsift bench` run and again before the
  Sprint 3 re-run, and neither file has changed; a later change to either is listed here with its reason.
- Mid-run correction, not a weights or corpus change: the `legacy_font` generator moved the short-i matra at
  sites where the previous cluster was not a word boundary although it had declared those sites ineligible
  (recall 20/24 in a test before the first bench run); the sites now agree. D3-03

### Fixed

- Notices (BUG-T3-S4-18): strsim 0.11.1 (MIT, CLI binary only; not in the wheel, npm package or demo) added to NOTICE with its
  copyright lines and MIT text; the sentence naming crates not offered under Apache-2.0 now names zmij, memchr and strsim.
- `tests/scripts/package-npm-default-scratch.sh` builds the CLI with `--locked` (BUG-T2-S4-07).
- `docs/release.md` has a History section naming the four trailer-carrying commits on the stale remote dependabot branch (BUG-T3-S4-13).

- BUG-T2-S3-19-R2: `scripts/package-npm.sh` failed on macOS with its default scratch folder. npm writes the tarball's
  `file:` dependency relative to the real path of the install directory and `npm ls --prefix` resolved it from the path
  it was given, so a scratch path through the `/var` link made `npm ls` report the one installed package as invalid
  (`ELSPROBLEMS`) when the checkout and the scratch folder shared a leading directory, as T2's checkout under
  a temp directory did. The script now resolves the checkout path and `SCRATCH` to physical paths (`pwd -P`) before npm sees
  them. Test first: `tests/scripts/package-npm-default-scratch.sh`, added to `tests/scripts/run-all.sh` and to the CI
  packaging job. D3-01
- BUG-T1-S3-R2-01: the demo's NOTICE link downloaded the file instead of showing it (Pages serves a file with no extension
  as `application/octet-stream`). The demo now serves `NOTICE.txt` (`text/plain`) and the footer links it; the demo check
  asserts the content type and that Chrome displays it with no download. D3-03

- `clusters` is named next to `validate` under the 4 MiB input limit in the README limitations, the Python
  binding README and docs/devanagari-rules.md section 5 (BUG-T2-S2-16); the README Windows line records the first green Windows determinism run (9 Nov 2026).
- `scripts/install-wasm-tools.sh` is fully re-synced from pagetriage's final copy: `mkdir -p "$ROOT"` now runs
  after both digest lookups, so an unknown tool version exits 1 without leaving the install directory behind;
  it differs from pagetriage's only on the four lines that name the repository (BUG-T2-S2-10, T3-S2-R1-01, S1-065)
- The README Benchmarks tables are regenerated from `docs/score-vs-noise.csv`, rounded half-up to four decimals
  (they had been truncated, so 19 of 45 cells were off by 0.0001); the CSV, SVG, weights and corpus are unchanged
  (BUG-T2-S2-11)
- Python `glyphsift.clusters()` refuses input over 4 MiB with the same `ValueError` as `validate()`, so native,
  Python and WASM agree at the limit; exactly 4 MiB is still accepted; the check lives in
  `tests/determinism/run_python.py` (BUG-T2-S2-12)
- `scripts/build-wasm.sh` refuses (exit 2) a `WASM_OUT` that is empty, absolute or has a `..` segment, then
  cleans with `rm -rf "./$OUT"`, so stale files cannot survive and an absolute path is never deleted; identical
  to the guard in pagetriage. `scripts/install-wasm-tools.sh` is re-synced from pagetriage and differs only on
  its four glyphsift-specific lines. BUG-T2-S2-08
- The CLI no longer prints a JSON error object and exits 3 on every input. D3-05
- `crates/glyphsift-py` now carries the `README.md`, `LICENSE` and `NOTICE` files its
  `pyproject.toml` names, so `uvx maturin build --release` produces the cp39-abi3 wheel (it failed
  with "Failed to read readme specified in pyproject.toml").
- Sprint 3 fix round 2: the demo serves `LICENSE` and a `NOTICE` that appends the MIT texts of the two WASM
  crates not offered under Apache-2.0 (memchr, zmij; `scripts/demo-notice-extra.txt`), the page footer links
  it, and `tests/demo/check_demo.mjs` checks both. T3-S3-023
- Sprint 3 fix round 2: every 8 GB Windows no-GPU laptop cell in the README Benchmarks tables reads exactly
  "not measured" (the score tables had read "not applicable (deterministic score)"), and the CLI test now
  requires that wording in all three tables.
- Sprint 3 fix round 2: "byte-identical across native, Python and WASM" is qualified "for valid Unicode text"
  in the README API and determinism sections, the Benchmarks note and `docs/devanagari-rules.md`.
  BUG-T2-S3-22-R2
- Sprint 3 fix round 2: `NOTICE` and its copies in the crates are derived with
  `cargo tree -e normal --target all` and now list the Windows-only crates windows-sys, windows-link and
  once_cell_polyfill; `*.tgz` is git-ignored; the README install citations point at the round-2 wheel, npm
  and CLI install logs; the Python binding README builds with `scripts/remap-paths.sh` and `maturin@1.16.0`.
  These changelog lines close BUG-T2-S3-21-R2.

### Dependencies

- `serde`, `serde_json` (no `preserve_order`), `thiserror`, `unicode-segmentation` and (Sprint 2)
  `unicode-general-category` in the core; `clap` in the CLI; `toml` as a dev-dependency to read the case
  table and the weights file in tests. All permissively licensed; `cargo deny` accepts the tree.
