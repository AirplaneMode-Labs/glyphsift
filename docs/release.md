# Release checklist

One row per item of the definition of done that every Airplane Mode Labs release must meet. A row is
Done only when the Evidence column names a file or command that proves it today; anything else is
Open. Nothing may be tagged while a Blocker-for-tag row is Open. The release is 0.1.3, a release candidate: the
workspace version is 0.1.3 (0.1.0, 0.1.1 and 0.1.2 were never tagged and 0.1.3 supersedes them, TD-43, TD-69 and TD-107), the notes live in
[CHANGELOG.md](../CHANGELOG.md) (`## [0.1.3] - 2026-11-20 (untagged)`), and
the owner's steps, in order, are in [RELEASING.md](RELEASING.md) (the release commit only changes that heading to a date).

Status as of 2026-11-20 (Sprint 7, an addition the owner asked for on 19 Nov 2026: release readiness; it has no row in the plan documents and creates no gate-1 evidence). Evidence paths under `evidence/sprint-3/D3/` to
`evidence/sprint-7/D3/` are copied there from the sprint scratch folders by the architect at wrap-up. Nothing is
published, signed or tagged, and the npm scope `@airplanemode` and the PyPI and crates.io names `glyphsift`,
`glyphsift-core` and `glyphsift-cli` are not reserved. The main session pushed Sprint 6 on 19 Nov 2026 (glyphsift at f9e88f4): CI run 44584716730 was green on all 15 jobs and the live demo shows Sprint 6 (read with `gh` on 20 Nov 2026).
Sprint 7 (version 0.1.3, the `release-rehearsal (<os>)` job, the vendored release tool, `publish.yml` and its guard, the quick start, the issue forms) is committed locally and not pushed, so no CI run covers it and the live demo changes only after the main session's push.
What the team could do is done: the rehearsal installs every built artefact into a fresh place and signs and verifies a rehearsal manifest with the published test key, and `publish.yml` exists behind six locks. Every row that is still Open needs the owner:
the 8 GB laptop (not measured on 8 GB), the real key, the reserved names, the configured environment with its variable and secrets, the tag, the publish and the write-up.

| # | Definition-of-done item | Status | Evidence | Owner | Blocker-for-tag |
|---|---|---|---|---|---|
| 1 | Tests written before the implementation; CI green on Linux, macOS and Windows | Tests-first evidence Done (red logs older than green logs, `evidence/sprint-7/D3/red/` and `green/`); CI was green on all 15 jobs at f9e88f4 (the Sprint 6 head, run 44584716730, read with `gh` on 20 Nov 2026); the Sprint 7 commits have not run in CI, pending the main session's push | Owner (reads CI after the main session's push): `gh run list --repo AirplaneMode-Labs/glyphsift --limit 5`, then every job by name, the three `release-rehearsal (<os>)` jobs first ("Sprint 7: what only CI can prove" below). Tests first, each with its red log before its green log: Sprint 3 to 6 in `evidence/sprint-3/D3/` to `evidence/sprint-6/D3/`, Sprint 7 in `evidence/sprint-7/D3/` (the release policy rules, the rehearsal, the vendored tool and its 36 shared vectors, the publish guard, the quick start, the community files) | owner (reading CI) | yes |
| 2 | Benchmark on an 8 GB laptop recorded in the README | Open | Owner must: run `node scripts/throughput.mjs corpus-1mib.txt --cli target/release/glyphsift` and the browser run on the 8 GB Windows no-GPU laptop (steps under "Owner must", row 2). README [Benchmarks](../README.md#benchmarks) carries Apple-silicon figures (the raw files [benchmarks/throughput-m5pro-48gb.json](benchmarks/throughput-m5pro-48gb.json) and [benchmarks/demo-1mib-m5pro-48gb.json](benchmarks/demo-1mib-m5pro-48gb.json), measured at 3c0bb4d on 20 Nov 2026 by `scripts/throughput.mjs --json` and `tests/demo/check_demo.mjs --bench-json`; the Sprint 3 and Sprint 5 logs they replace record no commit: raw data not kept) next to an "8 GB Windows no-GPU laptop" column that reads "not measured on 8 GB". No figure for that machine exists and none was invented. The procedure is below | owner | yes |
| 3 | README limitations section | Done | README [Limitations](../README.md#limitations): structural checks only, synthetic text only, Devanagari only, what the joiner and tag rules do and do not flag, the benchmark proves a narrow thing, nothing published, one wheel platform, nothing signed, CI not yet run on the Sprint 3 changes, target hardware unmeasured. The wheel and npm READMEs carry their own Limitations sections | D3 | no |
| 4 | Signed artifacts and manifest | Open (rehearsed with a public test key, not performed) | Owner must: create the real key offline, commit its public half to `docs/release-keys.json`, sign the manifest of the checked candidate with `cp-sign sign --no-expiry`, attach it to the GitHub release ([RELEASING.md](RELEASING.md), steps 3, 4, 11, 12, 13). Done by the team: `scripts/release/rehearse.sh` builds the artefacts as a release would, writes the manifest and `SHA256SUMS` with the vendored release tool (`scripts/release/release-tool.mjs`, spec 0.6.1, TD-103), signs a `glyphsift-rehearsal` manifest with the published RFC 8032 test key, verifies it with the explicit flag and shows `refused: test_key_refused` without it, `refused: no_trusted_key` against the committed empty `docs/release-keys.json`, and four more exact refusals; two runs with the same `SOURCE_DATE_EPOCH` gave byte-identical `SHA256SUMS` and `release-manifest.json` (`evidence/sprint-7/D3/green/rehearse-macos-run1.log` and `-run2.log`). That signature proves the tooling only: it is not a release signature, the test key can never sign a `-release` id (R1) and is refused by every production path (R2), and no signed manifest or real key exists | owner, D6 (cp-sign) | yes |
| 5 | CHANGELOG and semver tag | Open | Owner must: [RELEASING.md](RELEASING.md), step 9 (date the entry, read CI, `git tag -s v0.1.3`, push the tag), after rows 1, 2, 4, 6, 7 are Done. [CHANGELOG.md](../CHANGELOG.md) has `## [0.1.3] - 2026-11-20 (untagged)` (Keep a Changelog groups Added, Changed, Fixed, Security, Deferred; `[Unreleased]` is empty). The tag does not exist (`git tag` prints nothing) and must not be created until every row above and below is Done. The workspace version is 0.1.3 (`tests/scripts/release-doc.sh` checks that every crate, `Cargo.lock`, the wheel and the npm package.json carry the same one) | owner | yes |
| 6 | Package installable from a clean machine | Open (the rehearsal proves the install from the built files; nothing is published) | Owner must: reserve the names, configure the environment, publish through `publish.yml`, then install from a clean machine ([RELEASING.md](RELEASING.md), steps 2 to 16). Done by the team, on macOS arm64 from the 0.1.3 build in a copy with no sibling repository: each built artefact installed into a fresh place and called, with the output compared with committed bytes (a clean and a corrupted Devanagari sample, gate verdicts pass and hold): the tarball `airplanemode-glyphsift-0.1.3.tgz` into an empty npm project (offline, a fresh cache, `--ignore-scripts`), the wheel `glyphsift-0.1.3-cp39-abi3-macosx_11_0_arm64.whl` (about 248 KiB; the exact byte count varies by a few bytes with the checkout path, because the compiled extension is not byte-identical across build paths, so exact bytes are reproducible only from the same path (BUG-T3-S6-R2-08)) into a fresh `.venv` (`PIP_NO_INDEX=1`), and the CLI built by `cargo install --offline --locked` from the unpacked packaged `.crate` files with `glyphsift-core` taken from the packaged file and nothing from a registry (`evidence/sprint-7/D3/green/rehearse-macos-run1.log`); `package-python.sh` (both venvs, `mypy --strict`), `package-npm.sh` (a bundler-free page in installed Chrome, 0 console errors) and `package-sdist.sh` again for 0.1.3 (`evidence/sprint-7/D3/green/package-python.log`, `package-npm.log`, `package-sdist.log`; the sdist is about 115 KiB, carries four repository-root files its tests read and builds `cargo build --locked` from its own pruned `Cargo.lock`, and `tests/scripts/sdist-locked.sh` runs `cargo test --locked --no-fail-fast -p glyphsift-core --features corrupt` from the unpacked tree with `tests/corrupt.rs` (28 tests) and `tests/gate_noise.rs` (3 tests) shown to have run). The sizes and SHA-256 of all of them, with the toolchain versions, are in `evidence/sprint-7/D3/gates-s7.log`, the one log this row cites for artifact sizes. Not closed: the Linux and Windows runs of the rehearsal (only the push shows them), nothing is published, the names are not reserved, and no clean machine has installed from a registry | owner | yes |
| 7 | Short write-up | Open | Owner must: finish and publish the write-up from the measured figures once row 2 has numbers ([RELEASING.md](RELEASING.md), step 16): draft exists; finishing it waits on the 8 GB figure (owner). The draft is `docs/writeup-0.1.3-draft.md`, marked draft, not published, written from committed files only; the demo page at <https://airplanemode-labs.github.io/glyphsift/> is the natural home | owner | yes |

Blocker-for-tag rows Open today: 1, 2, 4, 5, 6, 7. Tagging v0.1.3 today would not be honest.

## Sprint 4 carry-overs closed here (D3)

| Item | Status | Evidence |
|---|---|---|
| BUG-T2-S3-19-R2: `scripts/package-npm.sh` fails on macOS with its default scratch folder | Fixed. The scratch folder and the checkout path are resolved to physical paths before npm sees them. Test first: `tests/scripts/package-npm-default-scratch.sh` fails with the old script (npm `ELSPROBLEMS`, as T2 saw from a checkout in a temp directory) and passes with the fix; the old script passed from a checkout in the home directory, which is why the test also builds the layout under the temp area. The tarball built before the NOTICE change was byte-identical to Sprint 3 (sha256 de2efaef...) | `evidence/sprint-4/D3/red-D3-01.log`, `green-D3-01.log`, `red-D3-01-private-tmp-checkout.log`, `green-D3-01-private-tmp-checkout.log` |
| S1-079: hashed, binary-only tool installs in the `packaging` and `demo-browser` jobs | Configured, run locally where this Mac can: the hashed install into fresh venvs (Python 3.12 and 3.15), `npm ci --ignore-scripts` from the lockfile, `package-python.sh` with the hashed venv. Proven only by CI after the owner's push: the same installs on the Ubuntu and Windows runners | `hashed-install-py3.12.log`, `hashed-install-py3.15.log`, `hashed-install-crossplatform-dryrun.log`, `npm-ci-playwright.log`, `package-python-hashed-venv.log` |
| Linux and Windows wheels and an sdist in CI | Configured in Sprint 4 (the `wheels` job; publishes nothing, no secrets). Ran for the first time in run 43667702791 at 5ff0c47 and was green on all three operating systems; read in Sprint 5 | see "First CI run of the wheels job" |
| BUG-T1-S3-R2-01: the demo's NOTICE link downloads instead of displaying | Fixed: the demo serves `NOTICE.txt` (text/plain) and the footer links it; Chrome shows it with no download | `red-D3-03.log`, `green-D3-03.log` (145 demo checks) |
| zmij attribution (TD-05) | Settled. Upstream `LICENSE-MIT` has no copyright line and is word for word the registry copy; the notice names David Tolnay from the crate's `Cargo.toml` and carries the full MIT text. The root `NOTICE` carries the attribution sentence and points to the text | `zmij-upstream.log` |
| Tamil design note (TD-18) | Written, no code: [v0.2-tamil.md](v0.2-tamil.md). Tamil planned for v0.2, Bengali later | the note itself |

## Sprint 5 carry-overs closed here (D3)

| Item | Status | Evidence |
|---|---|---|
| S1-103 / BUG-T2-S4-21: the sdist builds `--locked` from its own `Cargo.lock` | Fixed. Reproduced first: `maturin sdist` wrote a workspace with two members (`glyphsift-core`, `glyphsift-py`) beside the whole workspace's lock (61 entries), so `cargo build --locked` on the unpacked sdist stopped with "cannot update the lock file". `scripts/package-sdist.sh` builds the sdist, `scripts/prune-sdist-lock.py` cuts the 25 entries no member reaches (36 remain, same versions and checksums), and the script unpacks the result and builds it `--locked` with the lock left byte-identical. The CI `wheels` job calls the script for its sdist and the `packaging` job runs the test | `evidence/sprint-5/D3/red/sdist-locked-repro.log` then `green/package-sdist.log`; `tests/scripts/sdist-locked.sh` (21 checks); `red/D3-02.log`, `green/D3-02.log` |
| BUG-T3-S4-24: row 6 cites two different logs for the artifact sizes | Fixed at 5ff0c47 (row 6 cited only the gates-fix2 log) and now pinned: `tests/scripts/release-doc.sh` fails unless row 6 names exactly one `gates-*.log`. Row 6 now cites `gates-s5.log` alone, since the artifacts are 0.1.1 | `tests/scripts/release-doc.sh`; `red/D3-03.log`, `green/D3-03.log` |
| The first CI run of the `wheels` job | Read with `gh` (read-only) on 18 Nov 2026 and recorded in the next section | run 43667702791 at 5ff0c47; job logs copied to `evidence/sprint-5/D3/ci/` |
| The gate call (TD-42): `gate(text, threshold_ppm)` identical across core, WASM, Python and the CLI | Implemented tests first: rules and boundaries, 10,000 seeded random strings and the 4 MiB boundary (no panic), a 200-case corpus byte-identical on native, Python and WASM with the ill-formed cases rejected by every binding, a 40,000-probe fuzz hash shared by native and WASM, and the noise tables behind the default threshold. Rules and derivation: [gate.md](gate.md) | `red/D3-01.log`, `green/D3-01.log`, `green/determinism.log`, `green/gates.log` |
| Version 0.1.1 (TD-43) | Workspace, every crate, `Cargo.lock`, the wheel and the npm package.json carry it | `tests/scripts/release-doc.sh`, `gates-s5.log` |
| The `doc` CI job (BUG-T2-S4-22, conventions table) | `RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked` passes locally; the job is configured | `green/gates.log`, `tests/scripts/ci-policy.sh` section H |
| The `wheels` job checks each platform's wheel with `tests/python/check_wheel.py` | New. Run 43667702791 installed and called each wheel but did not check its contents (stubs, `py.typed`, LICENSE, NOTICE, README wording, sizes): only the `packaging` job's own native wheel went through that check | `.github/workflows/ci.yml`, `tests/scripts/ci-policy.sh` section G |
| BUG-T2-S5-02 / T3-S5-02 / S1-111, TD-53: glyphsift's `--out` containment | Fixed by porting pagetriage's `scripts/lib/confine.mjs`, its unit tests and its script-test changes (decision TD-53 puts glyphsift in Part A). T2 had reproduced on macOS, against the Sprint 5 script: `DIST/x.json` falsely refused (a string compare of two spellings of one directory), a symlink to a file inside `dist/` accepted and written through, a hard link to a file outside `dist/` overwritten (the other name's bytes changed), and two stack traces (a file used as a directory, a 300-character name). Tests first: the new `confine.test.mjs` fails to load without the library, and the new `release-manifest.sh` fails 10 checks against the old script; both pass after the port (36 tests, 68 checks, 0 skipped). Windows, where `ln -s` copies unless `MSYS=winsymlinks:nativestrict`, is proven only by the Windows CI leg after the push | `red/D3-FIX1-02-*.log`, `green/D3-FIX1-02-*.log`; section "Output confinement of `release-manifest.mjs`" below |
| BUG-T2-S5-07: a local macOS wheel is not byte-reproducible across checkout paths | Documented, no build change: see "Packaging notes" below | `tests/scripts/release-doc.sh` section D |
| BUG-T2-S5-08: `cargo doc` printed "output filename collision" between `glyphsift-py` (lib) and `glyphsift-cli` (bin) | Fixed: the CLI's `[[bin]]` is `doc = false`; `tests/scripts/ci-policy.sh` section J runs `cargo doc` and fails on the word "collision" | `red/D3-FIX1-04.log`, `green/D3-FIX1-04.log` |
| T3-S5-05, TD-56: the sdist ships `crates/*/tests` | Decided, no packaging change: the sdist is a source release and includes the tests on purpose ("Packaging notes" below) | `tests/scripts/release-doc.sh` section D |
| T3-S5-03 and T3-S5-15: README and CHANGELOG throughput figures differ from the log they cite; the 8 GB column says only "not measured" | Fixed: every figure equalled `evidence/sprint-5/D3/green/throughput.log` (gate 40 ms, validate 234, score_ppm 80, check 67, native gate 17; that log records no commit, so these Sprint 5 figures are raw data not kept) and every 8 GB cell reads "not measured on 8 GB". Since 20 Nov 2026 section C reads [benchmarks/throughput-m5pro-48gb.json](benchmarks/throughput-m5pro-48gb.json), which is committed | `tests/scripts/readme-claims.sh` sections B and C |
| BUG-T1-S5-05 / T3-S5-04: the README's first Status line is not the status line the demo and `site/data/demos.json` carry | Fixed: the first line of the README's Status section is the status line verbatim, the narrative follows it | `tests/scripts/readme-claims.sh` section A |

## Sprint 6 carry-overs closed here (D3)

| Item | Status | Evidence |
|---|---|---|
| S1-118 (a), BUG-T2-S5-16: the native determinism leg ignored `CARGO_TARGET_DIR` and could test a stale binary | Fixed: `tests/determinism/run_gate_native.mjs` looks in `${CARGO_TARGET_DIR:-target}/release` and prints `cli: <path>`; `scripts/determinism.sh` needed no other change (its `cargo run` already honoured the variable) | `tests/scripts/cargo-target-dir.sh`: red (the leg failed with ENOENT on a scratch checkout) then green, `red/D3-01-ctd.log`, `green/D3-01-ctd.log` |
| BUG-T2-S5-14 rest: `scripts/build-wasm.sh` ignored `CARGO_TARGET_DIR` | Fixed: the raw wasm is read from `${CARGO_TARGET_DIR:-target}/wasm32-unknown-unknown/wasm/`; the same test builds the web and nodejs packages from a scratch checkout with the variable set | same test, same logs |
| S1-118 (b), BUG-T2-S5-15: two shipped test files never ran, one fails when run | Fixed: the sdist test runs `--features corrupt` and counts both binaries (`corrupt.rs` 28 tests, `gate_noise.rs` 3); the failing one needed `docs/corruption-generator.md`, now shipped. The CLI's corrupt test is not in the sdist, with the reason above | `tests/scripts/sdist-locked.sh` (33 checks); `red/D3-01-sdist.log` (2 checks failed: the files did not run) then `green/D3-01-sdist.log`, `green/sdist-locked-final.log` |
| BUG-T2-S5-16 (the second half): row 6 cited a log with no `cargo test` | Fixed: row 6 cites `evidence/sprint-6/D3/gates-s6.log`, which holds the sdist's `cargo test --features corrupt` run and the artifact sizes; `tests/scripts/release-doc.sh` section F pins it | `tests/scripts/release-doc.sh` |
| `docs/what-glyphsift-measures.md` (D3-03) | New: every number is re-read from the committed file it cites by `tests/docs_numbers.py`; it fails if a cited CSV value is changed (mutation run: `green/D3-03-mutation.log`). It is the only text the outreach drafts may quote | `green/D3-03.log`, `red/D3-03.log` |
| Version 0.1.2 (TD-69) | Workspace, every crate, `Cargo.lock`, the wheel and the npm package carry it | `tests/scripts/release-doc.sh`, `gates-s6.log` |

Not closed in Sprint 6, and the owner's push list for it (nobody re-runs CI; each line names the job that proves the change):

- glyphsift | packaging dry runs (wheel, npm tarball, release manifest) | proves S1-118: the step "Script tests" runs `tests/scripts/sdist-locked.sh`, whose log must show `tests/corrupt.rs ran in the unpacked sdist and 28 tests passed` and the same for `gate_noise.rs` with 3, and `tests/scripts/cargo-target-dir.sh` (BUG-T2-S5-14) passing. The `wheels` job (display name "wheel and sdist (ubuntu-latest)") builds the sdist with `scripts/package-sdist.sh` and builds it `--locked`, but does not run `cargo test`.
- glyphsift | fmt, clippy, test, wasm32, pyo3 (ubuntu-latest, macos-latest, windows-latest) | proves the fix of the one red job of CI run 44580204699 (`packaging dry runs`, on S1-118: the log parser of `sdist-locked.sh` could not read cargo's coloured `Running` line under the workflow's `CARGO_TERM_COLOR=always`; CHANGELOG, Unreleased): the step "Cargo test log parser" runs `tests/scripts/cargo-test-log.sh` with `GLYPHSIFT_LIVE_CARGO_LOG=1`, and its log must show `CARGO_TERM_COLOR=always put escape bytes into the log file`, `live: tests/corrupt.rs ran and 28 tests passed` and the same for `gate_noise.rs` with 3 on all three systems. The `packaging` job's `sdist-locked.sh` line above is then the one read for the sdist itself.
- glyphsift | determinism (windows-latest) | proves BUG-T2-S5-14 on Windows: the native leg's log prints `cli: ...\target\release\glyphsift.exe` (the default directory, unchanged) and ends `gate native: 200 cases match`.
- glyphsift | fmt, clippy, test, wasm32, pyo3 (windows-latest) | proves S1-106 and COM0/LPT0: the step "Release-manifest --out containment" runs `confine.test.mjs` (43 tests, 0 skipped, the Sprint 6 cases included) on a real NTFS runner. Landed in D3-02 (`red/D3-02.log`, `green/D3-02.log`); the case list equals pagetriage's (`logs/confine-caselist-diff.txt` is empty).

## Sprint 7 carry-overs closed here (D3)

Sprint 7 is release readiness (an addition the owner asked for on 19 Nov 2026; no row in the plan documents; no gate-1 evidence). Version 0.1.3 (TD-107). Evidence under `evidence/sprint-7/D3/`; red logs are older than green logs.

| Item | Status | Evidence |
|---|---|---|
| Part A, CI at the Sprint 6 head | Read with `gh` on 20 Nov 2026: ci run 44584716730 at f9e88f4 green on all 15 jobs, pages run 44584717262 green; 0 open Dependabot pull requests (B5: nothing to apply or defer) | `partA-ci.log`, `dependabot.md` |
| The release tool vendored from runtime's spec 0.6.1 (D3-01, TD-103, TD-104) | `scripts/release/release-tool.mjs` byte for byte (sha256 `81583057...` since fix round 1, `57c2af90...` before), `scripts/release/VENDORED.json`, 31 shared vectors under `scripts/release/vectors/`, all `-text`; 35 of 36 cases run on macOS and Linux, the junction case on Windows only; manifest parity with `scripts/release-manifest.mjs` | `tests/scripts/release-tool-vendored.sh` (25 checks), `red/D3-01-vendored.log`, `green/D3-01-vendored.log` |
| `release-rehearsal (<os>)` replaces the `wheels` job (D3-02, TD-106, TD-118) | `.github/workflows/ci.yml`: ubuntu, macos and windows, `contents: read`, no cache, no secret, hashed tools, `--locked`; runs `scripts/release/rehearse.sh`; uploads `dist-release/` and `dist-release-report/` only, named `REHEARSAL-test-key-NOT-A-RELEASE-glyphsift-<os>-<sha>`, 3 days. Run once on macOS in a copy with no sibling and `GITHUB_SHA` and `GITHUB_REF` cleared, twice with the same `SOURCE_DATE_EPOCH`: `SHA256SUMS` and `release-manifest.json` byte-identical | `tests/scripts/ci-policy.sh` rules K (red, then green), `tests/scripts/rehearse.sh` (62 checks), `green/D3-02-rehearse-macos-run1.log`, `-run2.log` |
| S1-126 and TD-123: the packaged crates stay in the signed set | `cargo package --workspace --locked` is run twice in every rehearsal and in the publish build and the two `.crate` files must be byte-identical; they were (macOS), and the publish job re-packages them with `--no-verify` (S1-131: nothing is compiled where the tokens are; the same bytes, proved by the rehearsal's four runs) and compares the digests with the signed manifest before it publishes. If they ever differ the rehearsal fails and the crates leave the signed set (RELEASING.md, step 14) | `green/D3-02-rehearse-macos-run1.log` ("ok: two cargo package --workspace --locked runs give identical .crate bytes"), `scripts/release/build-artefacts.sh` |
| No '-core' crate from a registry (D3-02) | The CLI is installed by `cargo install --offline --locked` from the unpacked packaged `glyphsift-cli` crate; `glyphsift-core` comes from the packaged file through a directory source made by `cargo vendor --locked` with a `.cargo-checksum.json` whose package hash is the `.crate` sha256; the log has no `Downloading`, `Downloaded` or `Updating` line | `scripts/release/install-crate-offline.sh`, the rehearsal logs |
| `publish.yml` and its checks (D3-03, TD-105, TD-122, TD-123, TD-121) | `workflow_dispatch` only, no inputs, main of this repository only; locks: repository and ref guard, the `release` environment, the arming variable (a step, because an environment's variables are not visible in a job-level `if`), the signed manifest verified against `docs/release-keys.json`, environment secrets only, `RELEASE_KEY_ID`; bindings: tag to commit, manifest version and id, no registry holds the version; then provenance, then publishing from the exact files. `scripts/release/publish-guard.sh` holds the checks, `tests/scripts/publish-guard.sh` proves each refusal (78 checks in the first pass, 117 after fix round 1) and rules L of `tests/scripts/ci-policy.sh` pin every one (each single mutation of the file turns one red). Nobody has run it | `green/D3-03-publish.log`, `red/D3-03-publish.log` |
| `docs/RELEASING.md` (D3-03) | Rewritten as the owner's 16 steps in order, each with the reason only the owner can take it, the exact `gh` commands for the environment, variable, secrets, PyPI pending publisher, token scopes and expiry, the candidate check before signing, the offline `cp-sign` signature, verification with the vendored tool and the revoke step | `tests/scripts/release-doc.sh` section J |
| Quick start (D3-04, TD-115, TD-116) | README `## Try it in two minutes` (CLI, Python and Node, no model, no download, no test key), run by `tests/scripts/quickstart.sh`; eleven single-block breaks each turn it red; the `Live demo:` line is in the first 12 lines | `green/D3-04-quickstart-breaks.log`, `tests/scripts/readme-claims.sh` section D |
| Issue forms, `SECURITY.md`, `CONTRIBUTING.md`, good-first-issue texts (D3-04, TD-117) | `.github/ISSUE_TEMPLATE/` with the required no-real-documents checkbox and a `SECURITY.md` contact link, blank issues off; five draft texts under `drafts/good-first-issues/glyphsift.md`, none filed | `tests/scripts/community-files.sh` |
| `docs/what-glyphsift-measures.md` stays in step (D3-04) | Re-read against the committed benchmark: no number changed; `tests/docs_numbers.py` now also requires the page to name the workspace version | `tests/docs_numbers.py`, `green/D3-04-docs-numbers.log` |
| Write-up draft (D3-06) | `docs/writeup-0.1.3-draft.md`, marked draft, not published; row 7 reads "draft exists; finishing it waits on the 8 GB figure (owner)" | `tests/scripts/release-doc.sh` section I |
| Demo refresh (D3-05) | Sprint 7 status line, one new "does not do yet" line (no signing key, no tag, release path rehearsed in CI with a public test key only), 249 checks green, 0 requests when idle; the live page changes only after the main session's push | `green/D3-05-demo.log` |

No 8 GB figure exists (not measured on 8 GB), nothing is published or signed, and no 0.1.x tag exists.

## Sprint 7 fix round 1 (D3)

Fix round 1 of Sprint 7 (the PO triage of 20 Nov 2026). Red logs are older than green logs; the evidence is under `evidence/sprint-7/D3/` (`red/FR1-*.log`, `green/FR1-*.log`). Still true after it: not measured on 8 GB (no 8 GB figure exists), nothing is signed, published or tagged, and no step the team could have taken is left to the owner.

| Item | Status | Evidence |
|---|---|---|
| BUG-T3-S7-01 / S1-130: `npm publish verified/<name>.tgz` is a GitHub shorthand to npm | Fixed. npm's own `npm-package-arg` resolves a bare `verified/<name>.tgz` as the hosted spec `github:verified/<name>.tgz`, a third party's repository, so the first real publish would have tried to publish that. `publish.yml` now publishes `"./verified/$(cat lists/npm.txt)"` (resolved as type `file`); `scripts/release/publish-dry-run.sh` runs the identical string, with `--dry-run`, from a scratch directory laid out like the job's working directory (`verified/` and `lists/npm.txt`); rule M1 of `tests/scripts/ci-policy.sh` requires every `npm publish` argument in every workflow to start with `./` or `/` and the two strings to be equal | `tests/scripts/npm-publish-arg.sh` (6 checks; red: `git`, green: `file`), `red/FR1-S1-130-npm-publish-arg.log`, `green/FR1-S1-130-npm-publish-arg.log`, S1's own probe `green/FR1-S1-130-npa-probe-s1.log`, `green/FR1-publish-dry-run-local.log` |
| BUG-S1-S7-03 / S1-131: nothing is compiled in the job that holds the tokens | Fixed. The crates are packaged and published with `--no-verify` (`cargo package --workspace --locked --no-verify`, `cargo publish --workspace --locked --no-verify`). The re-package and the digest comparison against the signed manifest are one step with no token; the very next step publishes, with nothing between them; both come before the PyPI action (npm, then the crates, then PyPI); and `publish-guard.sh crate-index` then reads crates.io's sparse index until both crates show the signed sha256, asking again for 10 minutes on a 404, a server error or a missing line and failing at once on a different checksum, a yanked entry, two lines or a malformed one. `scripts/release/build-artefacts.sh` packages twice with the build check and twice with `--no-verify` and fails unless all four give the same bytes (macOS: identical); `publish-dry-run.sh` runs the workflow's command with `--dry-run` | `tests/scripts/publish-guard.sh` (117 checks, the index check run against stand-ins for `curl` and `sleep`), rules M7 of `ci-policy.sh`, `red/FR1-S1-131-publish-guard.log`, `green/FR1-S1-131-publish-guard.log`, `green/FR1-REHEARSE-macos-run1.log` |
| BUG-T3-S7-07: policy gaps and missing timeouts | Fixed, each rule with a mutation proven red (`tests/scripts/ci-policy-mutations.sh`, 84 checks: a control run and 83 single mutations of the workflows and release scripts): no install from the checkout in `release-rehearsal` or `publish.yml` (`cargo install --path`, `pip install -e .`, `maturin develop`); no `${{ }}` in a `publish.yml` `run:` step and no `${{ matrix.* }}` in a `run:` step of any workflow; the PyPI `packages-dir` is exactly the staging directory `pypi-dist/`; `timeout-minutes` 75 on the build job and 30 on the publish job; the `cargo-deny` job passes `matrix.checks` through step env as `CHECKS` and validates it | `red/FR1-ci-policy.log` (26 failures before the change), `green/FR1-ci-policy.log` (256 checks), `red/FR1-ci-policy-mutations.log`, `green/FR1-ci-policy-mutations.log` |
| TD-125 alignment | Confirmed and enforced: no `vars.` in any job-level `if` of any workflow; the armed check is step 2 of the publish job (right after the checkout) and `RELEASE_KEY_ID` is step 3; each variable is read once, in step env of the publish job; `docs/RELEASING.md` sets both with `--env release`, arms just before the approval and disarms after | rules M6 and their mutations |
| S1-135: the owner compares the candidate with an independent build before signing | `docs/RELEASING.md` step 11 names the independent build (the push run's `REHEARSAL-test-key-NOT-A-RELEASE-glyphsift-ubuntu-latest-<sha>` artefact or a local `scripts/release/rehearse.sh` at that commit with the pinned tools), the four files compared byte for byte (the npm tarball, the sdist and the two crates) with the `gh` and `shasum` commands, and says that wheels compare only between the two CI builds | `tests/scripts/release-doc.sh` section K |
| FR1-REVENDOR (follows BUG-T2-S7-04/05) | The release tool re-vendored from D1's re-landed spec 0.6.1 (`D1/RELANDED-FR1.txt`): sha256 `81583057...` (was `57c2af90...`) in `scripts/release/release-tool.mjs` and `scripts/release/VENDORED.json`; the 31 shared vectors are unchanged byte for byte (`diff -r` against runtime's `spec/vectors/release` is empty, listing sha256 `54d78d44...`); `release-tool-vendored.sh` 25 checks, `release-tool-cases.mjs` 35 of 35 on macOS (the junction case, 36 of 36, is Windows only); two sign phases with the same `SOURCE_DATE_EPOCH` are byte-identical | `red/FR1-REVENDOR-vendored.log` (the new pin against the old tool), `green/FR1-REVENDOR-vendored.log`, `green/FR1-REVENDOR-cases.log`, `green/FR1-REHEARSE-identical.txt` |

## Sprint 7: what only CI can prove (the push list)

The Windows and Linux legs cannot run on this Mac, and nobody on the team pushes or reruns CI. One line per job, in the form `<repo> | <job> | <task> | <what it proves> | <exact log text to look for>`; read each job's log after the main session's push.

- glyphsift | release-rehearsal (ubuntu-latest) | D3-02, D3-03 | the first run of the rehearsal on Linux: the manylinux_2_17 wheel through zig, the sdist built `--locked`, a wheel built from the unpacked sdist alone, the packaged crates, the CLI built from them with nothing from a registry, the publish dry runs, the test-key signature and the six refusals | `ok: two cargo package --workspace --locked runs give identical .crate bytes`, `installed node check: all checks passed`, `installed wheel check: all checks passed` (twice: the wheel and the sdist wheel), `installed cli check: all checks passed`, `Installed package` and a `Compiling glyphsift-core v0.1.3` line with no `Downloading` or `Updating` line, `release vectors through release-tool.mjs: 35 of 35 cases passed` (36 cases, the junction one is Windows only), `refused: test_key_refused`, `refused: no_trusted_key`, `release rehearsal ok on linux`; fix round 1: `ok: cargo package --workspace --locked --no-verify gives the same .crate bytes as the verified run, two runs each (S1-131)`, the dry run's `== 1. npm publish --dry-run (from a directory laid out like the workflow's, with the workflow's own ./verified/ argument)` followed by `+ @airplanemode/glyphsift@0.1.3`, and `== 2. cargo publish --dry-run --workspace --locked --no-verify` with two `aborting upload due to dry run` lines
- glyphsift | release-rehearsal (macos-latest) | D3-02, D3-03 | the same on a GitHub macOS runner (arm64): the wheel `macosx_11_0_arm64`, no sdist (a release builds it on Linux only) | the same lines with `release rehearsal ok on macos` and `release vectors through release-tool.mjs: 35 of 35 cases passed`; fix round 1: `ok: cargo package --workspace --locked --no-verify gives the same .crate bytes as the verified run, two runs each (S1-131)`, the dry run's `== 1. npm publish --dry-run (from a directory laid out like the workflow's, with the workflow's own ./verified/ argument)` followed by `+ @airplanemode/glyphsift@0.1.3`, and `== 2. cargo publish --dry-run --workspace --locked --no-verify` with two `aborting upload due to dry run` lines
- glyphsift | release-rehearsal (windows-latest) | D3-02, D3-03 | the first run of the whole path on Windows: `package-npm.sh` with `PACKAGE_NPM_PACK_ONLY=1` and `PYTHON=python`, `.venv/Scripts`, the cargo directory-source install and `glyphsift.exe` under `$RUNNER_TEMP`, and the Windows junction case of the shared vectors (a junction made with `fs.symlinkSync(..., "junction")`, refused with `not_regular_file`, never skipped: the Windows log must say `release vectors through release-tool.mjs: 36 of 36 cases passed`) | `release vectors through release-tool.mjs: 36 of 36 cases passed`, `installed wheel check: all checks passed`, `installed cli check: all checks passed`, `release rehearsal ok on windows`; fix round 1: `ok: cargo package --workspace --locked --no-verify gives the same .crate bytes as the verified run, two runs each (S1-131)`, the dry run's `== 1. npm publish --dry-run (from a directory laid out like the workflow's, with the workflow's own ./verified/ argument)` followed by `+ @airplanemode/glyphsift@0.1.3`, and `== 2. cargo publish --dry-run --workspace --locked --no-verify` with two `aborting upload due to dry run` lines
- glyphsift | packaging dry runs (wheel, npm tarball, release manifest) | D3-03, D3-04 | the new script tests on Linux: `publish-guard.sh` (117 checks), `release-tool-vendored.sh`, `rehearse.sh`, `quickstart.sh` (the quick start run from the built files), `community-files.sh`, and the rewritten `ci-policy.sh` and `release-doc.sh` | `script tests:` with `0 failed` and `quickstart: all blocks ran and the output matched`; fix round 1: the list also shows `npm-publish-arg.sh`, `ci-policy-mutations.sh` (`84 passed, 0 failed`) and `publish-guard.sh` (`117 passed, 0 failed`) with `0 failed`
- glyphsift | fmt, clippy, test, wasm32, pyo3 (ubuntu-latest, macos-latest, windows-latest) | D3-01 | version 0.1.3 and the README test of Sprint 7 (`readme_states_the_sprint_7_position_in_the_required_words`) | `test result: ok.` with 0 failed for every binary
- glyphsift | demo build (ubuntu-latest) and pages deploy | D3-05 | the demo builds and deploys with the Sprint 7 page | the pages run is green and the live page's status line begins `Sprint 7 (20 Nov 2026)`
- glyphsift | cargo-deny (advisories) | BUG-T3-S7-07 | the deny job with the matrix value passed through step env as `CHECKS` and validated: the step runs cargo-deny on `advisories` (this leg may report a new advisory, which is information and does not block) | the step runs to cargo-deny's own summary and the log has no line `unexpected cargo-deny checks`
- glyphsift | cargo-deny (bans licenses sources) | BUG-T3-S7-07 | the same step with the three words in `CHECKS`, unquoted on purpose so that cargo-deny gets three arguments | cargo-deny's summary reports `bans ok, licenses ok, sources ok`, and no line `unexpected cargo-deny checks`
- glyphsift | publish.yml | D3-03 | nothing: the team never runs it and no push, pull request or schedule can; a run of it in the list of workflow runs before the owner's step 10 would be a defect | `gh run list --workflow publish.yml` shows no run; what the owner's first real run must show, in order, at the crates: the step 'Re-package the crates (no build) and compare their digests with the signed manifest' prints `ok: glyphsift-core-0.1.3.crate re-packaged to the verified digest` and the same for the cli, the next step publishes without a build (`Uploading glyphsift-core v0.1.3`, no `Compiling` line), and the step 'The crates.io index shows both crates with the signed checksums' ends `ok: both crates are in the crates.io index at 0.1.3 with the signed cksums`

## First CI run of the wheels job (read on 18 Nov 2026)

Run [43667702791](https://github.com/AirplaneMode-Labs/glyphsift/actions/runs/43667702791), workflow `ci`, push to `main`, head
`5ff0c47ec1fcb0b8d1c80f0029aa89ab78e03d2e`, started 2026-11-15T02:25:18Z, finished 02:29:43Z, conclusion `success`: all 14 jobs
green, the three `wheels` jobs, the `packaging` job and the `demo-browser` job among them, none of which had run before (the last earlier run
was the Sprint 2 commit). Read on 18 Nov 2026 with `gh run view 43667702791 --repo AirplaneMode-Labs/glyphsift --json status,conclusion,headSha,jobs`
and `gh run view ... --job <id> --log`, plus `gh api` GETs for the job ids and the artifact list; nothing was changed or re-run.
Job logs: `evidence/sprint-5/D3/ci/`. Every size in this table is committed as raw data in [benchmarks/ci-run-43667702791.json](benchmarks/ci-run-43667702791.json), copied from the run's logs and artifact list (GitHub keeps both for a limited time,
and the three artifacts expire on 22 Nov 2026), and `tests/scripts/benchmarks-raw.sh` checks that this table and the file agree.

| Job (job id) | Built | File and size | Smoke call, builder-path gate | Workflow artifact (size) |
|---|---|---|---|---|
| wheel and sdist (ubuntu-latest) (132670667630) | `manylinux_2_17` wheel through zig, and the sdist | `glyphsift-0.1.0-cp39-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64.whl`, 254,335 bytes; `glyphsift-0.1.0.tar.gz`, 82,081 bytes | `ppm 1000000`; "ok: no builder path" on 9 files | `glyphsift-wheels-ubuntu-latest` (335,583 bytes) |
| wheel and sdist (windows-latest) (132670667625) | `win_amd64` wheel with MSVC | `glyphsift-0.1.0-cp39-abi3-win_amd64.whl`, 151,328 bytes | `ppm 1000000`; "ok: no builder path" on 9 files | `glyphsift-wheels-windows-latest` (150,241 bytes) |
| wheel and sdist (macos-latest) (132670667797) | macOS arm64 wheel | `glyphsift-0.1.0-cp39-abi3-macosx_11_0_arm64.whl`, 247,045 bytes | `ppm 1000000`; "ok: no builder path" on 9 files | `glyphsift-wheels-macos-latest` (245,793 bytes) |

What the run proved:

- The hashed tool install (`pip install --require-hashes --no-deps --only-binary=:all: -r tools/ci/requirements.txt`, maturin 1.16.0, ziglang 0.16.0)
  succeeds on the Ubuntu, Windows and macOS runners, and `maturin build --release --locked` builds a wheel on each. `npm ci --ignore-scripts` of the Playwright
  lockfile succeeds on Ubuntu (`demo-browser`; that job is Linux only, so npm on Windows is still unproven).
- The zig cross-compile path produces a `manylinux_2_17` wheel that installs into a fresh venv with `--no-index` and answers `ppm 1000000` on the Ubuntu runner.
- `scripts/remap-paths.sh` holds on Windows: the `win_amd64` wheel passed `scripts/check-no-builder-paths.py`. Sprint 4 listed this as the open question ("if it fails,
  fix the remap, not the gate"); it did not fail.
- `actions/upload-artifact` kept the wheel and the sdist (the names above), with `retention-days: 7`. The three artifacts expire on 22 Nov 2026
  (02:26:02Z, 02:26:40Z and 02:29:22Z); after that only a new run produces them.
- The other jobs that had never run were green too. `packaging`: the npm tarball (112,296 bytes), a native Ubuntu wheel (`manylinux_2_34_x86_64`, 270,214 bytes,
  a dry run, not the file to upload: its glibc floor excludes older distributions), `mypy --strict` on the stubs, and the five script tests (`script tests: 5 run, 0 failed`, the CI policy
  among them with 54 checks). `demo-browser`: `demo: all 150 checks passed` in Chrome under `/glyphsift/`, and the npm package in a bundler-free page.

What it did not prove:

- **S1-103.** The sdist was built (82,081 bytes), and the step then ran `git diff --exit-code -- Cargo.lock`, which only shows that the repository's lock did not change. Nothing built from the sdist.
  On 18 Nov 2026 the same `maturin sdist` unpacked and built `--locked` fails ("cannot update the lock file"): see the Sprint 5 table above for the fix.
- Nothing about a clean machine. Each wheel was installed on the runner that built it, into a fresh venv, and never anywhere else or from a registry.
- Nothing about reproducibility across machines. The same sources gave a macOS wheel of 247,045 bytes on the runner and 247,060 on this Mac (Sprint 4), and an npm tarball of 112,296 bytes on the runner and 112,744 locally (the runner's sizes are in the raw file above; the local ones, 247,060 and 112,744: raw data not kept). The
  cause was not investigated. Publish and sign the files from the one pipeline, never a local rebuild.
- Nothing about the contents of the Linux and Windows wheels: only the `packaging` job's own native wheel went through `tests/python/check_wheel.py`. The `wheels` job now runs it on every platform's wheel (Sprint 5, unrun).
- Nothing about 0.1.1. These are 0.1.0 artifacts at the Sprint 4 head. **Nothing is published**: the workflow artifacts are not releases, there was no registry, release, signing or Pages step, and no secret.
- The OS classifiers in `crates/glyphsift-py/pyproject.toml` stay `Operating System :: MacOS` and the matching assertion in `tests/python/check_wheel.py` stays, until the owner publishes CI-built wheels (row 6, step 2): the Sprint 4 wheels were
  installed by CI, but the 0.1.1 wheels have not been built.

## Packaging notes (Sprint 5, fix round 1)

**Local macOS wheels are not byte-reproducible across checkout paths.** Two builds of the same commit made in two different
directories (`scripts/package-python.sh`, the same flags, the path-remap prefixes set) give wheels that differ in exactly two
members: `glyphsift.abi3.so` and the `RECORD` that lists its hash (BUG-T2-S5-07: 254,146 and 254,149 bytes, 47 differing bytes
in the library, 16 of them the Mach-O `LC_UUID` load command and about 31 the linker-signed ad-hoc code signature that covers
it). A third build, in this checkout, gave 254,147 bytes (`gates-s5.log`), and a rebuild in the same checkout three hours later gave the same SHA-256, so the variation follows the path, not the time. The differences are the linker's, not
the source's: the Rust code and the Python files are identical. Only CI-built wheels are signed and published: the
owner signs the manifest of what the `wheels` job built (row 4), and a wheel built on a developer Mac, this one included, is
evidence that the package installs and runs, never a release artifact. No build change was made: removing the UUID
(`-Wl,-no_uuid`) and re-signing deterministically would change what a macOS user's crash reports and symbolication can
match, for no gain while nothing is published from a Mac. The Linux and Windows wheels have no such fields. (The byte counts in this paragraph, 254,146, 254,149 and 254,147, are from local builds: raw data not kept; they are build facts, not benchmarks.)

**The sdist is a source release and deliberately includes `crates/*/tests`** (TD-56; T3-S5-05). The sdist
carries seven test files, 111,928 bytes before compression in the 0.1.1 sdist (a size read from that build: raw data not kept; it is a build fact, not a benchmark; the Rust test sources and the 35,270-byte synthetic case
table `crates/glyphsift-core/tests/cases/devanagari.toml`, which `wc -c` reproduces), and it ships four repository-root files its tests read, at the same relative paths:
`bench/corpus/clean.txt`, `docs/gate.md`, `docs/score-vs-noise.csv` and `docs/corruption-generator.md` (BUG-T2-S5-12 and, for the last, S1-118; all four are
synthetic and own-authored; maturin cannot include a path outside the Python project, so `scripts/add-sdist-files.py` appends them). A person who
receives the sdist can therefore run `cargo test --locked --features corrupt` and see the 154-case table, the gate tests and the corruption-generator tests pass
without cloning the repository: `tests/scripts/sdist-locked.sh` runs `cargo test --locked --no-fail-fast -p glyphsift-core --features corrupt` in the
unpacked sdist, requires 0 failed with no `--skip` (before the Sprint 5 fix 3 of 14 gate tests failed), and requires `tests/corrupt.rs` and `tests/gate_noise.rs`
to have run with at least one test passed each. Those two files declare `required-features = ["corrupt"]`, so a plain `cargo test` skips them silently: that
was S1-118 / BUG-T2-S5-15, and `corrupt.rs` also failed when run because `docs/corruption-generator.md` was not shipped. The CLI crate, and so its own corrupt test
(`crates/glyphsift-cli/tests/corrupt.rs`), is not in the sdist: maturin ships only `glyphsift-core` and `glyphsift-py`, and the same script asserts it. No file in it is
a real document, a key or a model. `scripts/package-sdist.sh` builds the unpacked sdist `--locked` from its own pruned lock
(S1-103). If a later release wants a smaller sdist, the exclusion belongs in `crates/glyphsift-core`'s
`Cargo.toml` and in `pyproject.toml`'s maturin `include` list, with `tests/scripts/sdist-locked.sh` changed first.

## Output confinement of `release-manifest.mjs` (Sprint 5, Part A, TD-45 and TD-53)

`node scripts/release-manifest.mjs --out <file> <artifact>...` writes only to a regular file inside this repository's `dist/`.
The check and the write live in `scripts/lib/confine.mjs`, which is pagetriage's file of the same name (TD-53: the security review
found the same containment fault in glyphsift's own check; the two copies differ only in the header, and a change to one is made
to both). It takes `{pathMod, fs, platform}` so that every rule below is unit-tested on any OS (`tests/scripts/confine.test.mjs`,
with `path.win32` and an in-memory volume) and again against real files and real links (`tests/scripts/release-manifest.sh`).
Any refusal exits 2 and writes nothing; any other write error exits 1 with one line, never a stack trace.

Rules, in the order they are applied:

1. `--out` is not empty and has no NUL; no component is `..` (a backslash counts as a separator for this test on every OS).
2. On Windows only, on the text as typed: no `\\?` or `\\.` prefix; no UNC path (`\\server\share`, also `//server/share` and the
   admin share of the local drive); no drive-relative path (`C:name`, `C:dir\name`, `C:`), whose meaning depends on a per-drive
   working directory; no `:` after the drive (an alternate data stream); no reserved device name (`CON PRN AUX NUL COM0-9 LPT0-9
   CONIN$ CONOUT$`, plus the superscript digits 1 to 3 after COM and LPT; COM0 and LPT0 since Sprint 6, T2-NOTE-COM0; any case, with or without an extension); no component ending in `.` or a space (Windows strips them); no
   character Windows forbids in a file name.
3. `dist/` and the deepest existing ancestor of `--out` are resolved with `fs.realpathSync.native`: on Windows that expands 8.3 short
   names, gives each name its on-disk case and follows every symlink and junction, including a reparse point that `lstat` does not
   report as a link; on a case-insensitive macOS volume it gives `DIST/` the on-disk case `dist/`, which is why a differently-cased
   spelling is accepted there. A dangling link on the way is refused.
4. If `--out` itself exists it must be a regular file. A symbolic link or junction is refused whatever it points at (a file inside
   `dist/` included), and so is a directory, a FIFO, a socket or a device. A regular file or a dangling link at `dist/` itself is
   a one-line refusal.
5. Containment is two tests and both must pass (S1-106, Sprint 6). (a) `relative(distReal, final)` must be non-empty, not absolute
   (another drive) and not `..` or `..` plus a separator; a file called `..foo` is fine. (b) `final` must start with `distReal` plus a
   separator, compared exactly. `path.win32.relative` ignores case, but after step 3 both sides carry the on-disk spelling, so a case
   difference left over is a different directory (an NTFS directory with per-directory case sensitivity, `fsutil file
   setCaseSensitiveInfo`, WSL). On an ordinary case-insensitive volume every spelling of `dist/` resolves to the one on-disk name, so
   (b) accepts what (a) accepts. Elsewhere than Windows both tests are exact, so a difference in spelling can refuse a path but never
   accept one.
6. The bytes go to a temporary name (`.release-manifest-<random>.tmp`) opened with the `wx` flag inside the resolved parent, are
   flushed and are renamed over the target, after the parent has been resolved and checked a second time. `rename` replaces a
   link at the target instead of following it, and replaces a hard link's name without opening its inode: a file in `dist/` that is a
   second name (a hard link) of a file outside `dist/` is replaced by the manifest and the outside file keeps its bytes (T2's R34;
   the Sprint 5 script wrote through it with `writeFileSync`).

What is not closed: between the second check and the `rename` another process that can already write inside `dist/` could replace a
directory by a link. This is a local tool run by the owner on their own checkout, so that process would have to be the owner's own
account; the window is narrowed, not removed. `dist/` itself may be a link (the check is relative to what it resolves to). On a
case-sensitive directory a differently-cased spelling of `dist/` is another directory and is refused (test (b); proven on a model, not on a real case-sensitive NTFS directory: the Windows runner cannot make one without WSL).

How the Windows rules are proven here and where they are not. This Mac cannot run Windows. On macOS the same files give 43 unit
tests (the Windows rules through `path.win32`, an in-memory volume with 8.3 aliases, a hidden junction and a case-insensitive
directory, then real symlinks and hard links; 0 skipped) and 68 script checks, and the red logs show the differently-cased `dist/`
refusal that pagetriage saw on `windows-latest` reproduced on this case-insensitive APFS volume. What only Windows proves: that `ln -s`
under `MSYS=winsymlinks:nativestrict` makes a native link (each link is asserted with `[ -L ]` and a link that cannot be made fails
the run), that `cmd.exe /c mklink /J` run with MSYS argument conversion turned off makes a junction (`/c` and `/J` are switches; with
conversion on, Git Bash rewrites them into paths and no junction is made; the same junction case is repeated without a shell in
`confine.test.mjs`), and that `realpath.native` returns what the rules assume for 8.3 names on a runner. These are the legs the owner reads:
**glyphsift check (windows-latest) proves the ported containment** (the `check` job's step "Release-manifest --out containment" on
ubuntu-latest, macos-latest and windows-latest; it exists in no earlier run).

## What only CI can still prove (Sprint 5, after the owner's push)

| What only CI proves | Why not here |
|---|---|
| the sdist step of the `wheels` job (`scripts/package-sdist.sh`) builds the sdist, prunes its lock and builds it `--locked` on `ubuntu-latest`, and the `packaging` job's script tests (`sdist-locked.sh`, `release-doc.sh`) pass with the hashed maturin | this Mac builds and checks the same script with an unhashed `uvx maturin@1.16.0`; the hashed venv and the Linux runner are CI's |
| `tests/python/check_wheel.py` passes on the `manylinux_2_17` wheel built on `ubuntu-latest` (the `win_amd64` and macOS legs passed in run 44325740893) | no Linux machine. Run 44325740893 (b3ea291) failed this check on the Linux leg only: the filename's compressed tag set was compared as a string with the one-`Tag:`-line-per-tag `WHEEL` file. The check now compares expanded tag sets; `tests/python/test_check_wheel.py` reproduces the fault with synthetic wheels on macOS (red, then green) and the fixed script passes the real `0.1.0` manylinux wheel of run 43667702791, but only a new run of the ubuntu leg proves it on the wheel that leg builds |
| the `doc` job (`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked`) is green on `ubuntu-latest` | passes locally on macOS with the same flags |
| the gate determinism leg (200 cases, `scripts/determinism.sh`) is byte-identical on Ubuntu, macOS and Windows, including `isWellFormed` in Node 22 | this Mac only; Windows runs the corpus through Git Bash and `glyphsift.exe` |
| the demo's Gate tab passes `tests/demo/check_demo.mjs` (234 checks) in the runner's Chrome | passes in installed Chrome on this Mac |
| glyphsift check (windows-latest) proves the ported `--out` containment, including the Sprint 6 COM0/LPT0 and exact-case changes: `confine.test.mjs` (43 tests, none skipped) and `release-manifest.sh` with native symlinks asserted by `[ -L ]`, hard links, and a real junction made with MSYS conversion off | this Mac cannot run Windows; macOS ran the same two files (43 tests, 68 checks, 0 skipped) and reproduced the differently-cased `dist/` refusal, the write-through and the stack traces against the old script |
| the whole three-OS matrix for the Sprint 5 commit is green | nothing of Sprint 5 has been pushed |

Known gaps in the hashed installs (each in a job that publishes nothing and uses no secrets, `contents: read`):

- the pip that `actions/setup-python` ships is not pinned (the first `pip install --require-hashes` runs with it);
- `scripts/determinism.sh` installs `maturin==1.16.0` by version only (not by hash) into a test-only venv, in the
  `determinism` job, which builds a Python extension that is never shipped;
- the digest-pinned `wasm-bindgen` and `wasm-opt` release binaries (`scripts/install-wasm-tools.sh`) and `cargo-deny`
  are pinned by SHA-256, not by a lockfile.

Before the owner publishes the CI-built wheels: change the OS classifiers as described under row 6. (The wheel, the tarball and the sdist
already carry the MIT texts of zmij and memchr inside `NOTICE`, TD-28; the demo's `NOTICE.txt` is a copy.)

## Owner must

Each Open row that is yours, with the commands. The ordered list of everything the owner does to release, with the reason each step is the owner's, is [RELEASING.md](RELEASING.md); this section keeps the one
runbook that is not a release step, the 8 GB laptop (row 2). Run commands from a checkout of `AirplaneMode-Labs/glyphsift` (`cp-sign` comes from the private `AirplaneMode-Labs/control-plane`).

**Row 1, CI after the push.** The main session pushes between sprints and reads CI; the owner reads the jobs listed under "Sprint 7: what only CI can prove" below (`gh run list --repo AirplaneMode-Labs/glyphsift --limit 5`, then
`gh run view <run-id> --repo AirplaneMode-Labs/glyphsift --json jobs --jq '.jobs[] | [.name, .conclusion] | @tsv'`). Row 1 is Done only when every job is green for the commit that will be tagged.

**Row 2, benchmark on the 8 GB Windows no-GPU laptop.**

Owner must: run the steps below on the target machine itself (8 GB RAM, no discrete GPU, a current Windows 10 or 11,
Chrome) and write down what the commands print. Invent nothing. The throughput script is `scripts/throughput.mjs`
(`node scripts/throughput.mjs corpus-1mib.txt --cli target\release\glyphsift.exe`).

1. Record the machine: Windows version (`winver`), CPU model, RAM, whether a GPU is present
   (`Get-CimInstance Win32_VideoController`), Chrome version, and that Wi-Fi is off for the browser run.
2. Build the CLI and make the 1 MiB text (the corpus repeated line by line up to 1,048,576 bytes, as in
   [benchmarks/throughput-m5pro-48gb.json](benchmarks/throughput-m5pro-48gb.json), whose `data.input` records its size and SHA-256), then time it five times:

   ```sh
   cargo build --release -p glyphsift-cli
   node -e 'const fs=require("fs");const L=fs.readFileSync("bench/corpus/clean.txt","utf8").split("\n").filter((x,i,a)=>!(i===a.length-1&&x===""));let out="",bytes=0,i=0;for(;;){const l=L[i%L.length]+"\n";const n=Buffer.byteLength(l);if(bytes+n>1048576)break;out+=l;bytes+=n;i++}fs.writeFileSync("corpus-1mib.txt",out);console.log(i,"lines",bytes,"bytes")'
   ```

   Then, in PowerShell, five timings: `1..5 | ForEach-Object { (Measure-Command { .\target\release\glyphsift.exe check corpus-1mib.txt | Out-Null }).TotalMilliseconds }`.
   (The Node line was run on the Mac and gives the 12,888 lines and 1,048,569 bytes of `throughput-m5pro-48gb.json`; the PowerShell line
   was not run, there is no PowerShell here.)
3. WebAssembly: `scripts/install-wasm-tools.sh`, `scripts/build-wasm.sh` (Git Bash), then in Node
   `node tests/determinism/run_wasm.mjs` for correctness and your own `performance.now()` loop around
   `validate()` and `score_ppm()` from `dist/wasm/nodejs`, best of five; `node scripts/throughput.mjs corpus-1mib.txt` does exactly that
   and also times the native CLI. Add `--json docs/benchmarks/throughput-8gb.json` to write the raw file (date, commit, machine and all five runs), and `node tests/wasm/run_wasm_safety.mjs --bench-json docs/benchmarks/wasm-linearity-8gb.json` for the linearity ratio.
4. Browser: `scripts/build-demo.sh`, serve `demo/dist` under `/glyphsift/` (this does it and prints the 1 MiB time:
   `npm ci --prefix tools/playwright --ignore-scripts`, then
   `PLAYWRIGHT_DIR=$PWD/tools/playwright node tests/demo/check_demo.mjs --cli target/release/glyphsift --bench-json docs/benchmarks/demo-1mib-8gb.json`), turn Wi-Fi off, open it in Chrome, load a synthetic `.txt` file and note the time.
5. Peak memory: Task Manager, Details tab, "Peak working set (memory)" for the Chrome tab process, and for
   `glyphsift.exe` during the timing run. Write the figure and where it came from.
6. Commit the raw files under `docs/benchmarks/` (the three files named above; [benchmarks/README.md](benchmarks/README.md) says how to list them), put the results in the README Benchmarks table (the "8 GB Windows no-GPU laptop"
   column) from those files, and change row 2 to Done here.

**Rows 4 to 7.** [RELEASING.md](RELEASING.md), steps 2 to 16: reserve the names, create and commit the real key, configure the `release` environment, its variable and secrets, tag, dispatch `publish.yml`, check the candidate, sign it offline, attach
the signed manifest to the GitHub release, arm and approve, disarm and revoke, install from a clean machine, finish the write-up. The README Install section moves its "After the owner publishes" commands into the main text in step 16.

## History

Four commits on this repository carry attribution trailer lines in their messages (trailers are attribution metadata, not secrets or employer data). Values below come from read-only `git -C` commands (`git log --all`, `git branch -a --contains`).

| Commit | Date | Subject |
|---|---|---|
| 884e7a8 | 2026-11-09 | repo: licence, notice, CI skeleton |
| 0751b46 | 2026-11-09 | core: Devanagari cleanliness rules and report schema, with golden cases |
| fc01193 | 2026-11-09 | bindings: CLI, PyO3 wheel and wasm-bindgen package |
| 76d2070 | 2026-11-09 | docs: README, Devanagari rules and the corruption generator |

- Count: 4 commits, all dated 9 Nov 2026.
- Where they are: only on the remote branch `origin/dependabot/cargo/wasm-bindgen-0.2.130`. They are not on `main` (`git branch -a --contains <sha>` lists only that branch).
- What is left alone (team decision TD-01 under owner delegation, 14 Nov 2026): nothing here rewrites history or changes a remote branch. Deleting that remote branch is an owner step; nobody on the team deletes or changes remote branches.
