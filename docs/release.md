# Release checklist

One row per item of the definition of done that every Airplane Mode Labs release must meet. A row is
Done only when the Evidence column names a file or command that proves it today; anything else is
Open. Nothing may be tagged while a Blocker-for-tag row is Open. The release is 0.1.1, a release candidate: the
workspace version is 0.1.1 (0.1.0 was never tagged and 0.1.1 supersedes it, TD-43), the notes live in
[CHANGELOG.md](../CHANGELOG.md) (`## [Unreleased]` until the architect dates them as `## [0.1.1] - 2026-11-18 (untagged)`), and
the tag commit (step 1 below) only changes that heading to a date.

Status as of 2026-11-18 (Sprint 5). Evidence paths under `evidence/sprint-3/D3/`, `evidence/sprint-4/D3/` and
`evidence/sprint-5/D3/` are copied there from the sprint scratch folders by the architect at wrap-up. Nothing is
published, signed or tagged, and the npm scope `@airplanemode` and the PyPI and crates.io names `glyphsift`,
`glyphsift-core` and `glyphsift-cli` are not reserved. The owner pushed Sprints 3 and 4 on 15 Nov 2026 (glyphsift at
5ff0c47): CI run 43667702791 was green on all 14 jobs and the live demo shows Sprint 4 (read on 18 Nov 2026; the section
"First CI run of the wheels job" records what that run proved). Sprint 5 (the gate call, the sdist fix, version 0.1.1) is
committed locally and not pushed, so no CI run covers it and the live demo changes only after the owner's push. No row below
flips to Done in Sprint 5: every one needs the owner (the push and a CI read of the Sprint 5 commit, the 8 GB laptop, the real
key, the tag, the registries). What Sprint 4 and Sprint 5 closed, and what only CI can prove, are in the tables after the rows.

| # | Definition-of-done item | Status | Evidence | Owner | Blocker-for-tag |
|---|---|---|---|---|---|
| 1 | Tests written before the implementation; CI green on Linux, macOS and Windows | Tests-first evidence Done (red/green logs); CI was green on all three operating systems at 5ff0c47 (Sprint 4 head, run 43667702791); the Sprint 5 commit has not run in CI, pending the owner's push | Owner must: `git push`, then `gh run list --repo AirplaneMode-Labs/glyphsift --limit 5` and read every job (commands under "Owner must", row 1). Tests first, each with its red log before its green log: Sprint 3 and 4 in `evidence/sprint-3/D3/` and `evidence/sprint-4/D3/` (the case table, the wheel, the npm package, the CLI surface, the demo, the release-manifest tool, the hashed installs and the CI policy), and Sprint 5 in `evidence/sprint-5/D3/red/` then `green/`: D3-01 the gate (core tests, CLI tests, the 200-case corpus, the WASM safety script; `red/D3-01.log` then `green/D3-01.log`), D3-02 the sdist builds `--locked` (`red/D3-02.log`, `green/D3-02.log`), D3-03 this document and the version (`red/D3-03.log`, `green/D3-03.log`), D3-04 the demo's Gate tab (`red/D3-04.log`, `green/D3-04.log`). Local macOS arm64 at Sprint 5: `cargo fmt`, `clippy -D warnings`, `cargo test`, `RUSTDOCFLAGS="-D warnings" cargo doc`, `scripts/determinism.sh` (native, Python and WASM byte-identical on 13 samples and on 200 gate cases), `cargo deny check bans licenses sources` and the script tests pass (`evidence/sprint-5/D3/green/gates.log`). The three-OS matrix (`check`, `determinism`, `deny`, `demo`, `packaging`, `demo-browser`, `wheels`, and new in Sprint 5 `doc`) is configured in `.github/workflows/ci.yml`. At 5ff0c47 it was green: [run 43667702791](https://github.com/AirplaneMode-Labs/glyphsift/actions/runs/43667702791), all 14 jobs, including the `packaging`, `demo-browser` and `wheels` jobs that had never run before. Not marked Done until the owner pushes the Sprint 5 commit and reads CI for it | D3, then owner (push, read CI) | yes |
| 2 | Benchmark on an 8 GB laptop recorded in the README | Open | Owner must: run `node scripts/throughput.mjs corpus-1mib.txt --cli target/release/glyphsift` and the browser run on the 8 GB Windows no-GPU laptop (steps under "Owner must", row 2). README [Benchmarks](../README.md#benchmarks) carries Apple-silicon figures (`evidence/sprint-3/D3/throughput.log`, and for the gate rows added in Sprint 5 `evidence/sprint-5/D3/green/throughput.log`, from `scripts/throughput.mjs`) next to an "8 GB Windows no-GPU laptop" column that reads "not measured on 8 GB". No figure for that machine exists and none was invented. The procedure is below | owner | yes |
| 3 | README limitations section | Done | README [Limitations](../README.md#limitations): structural checks only, synthetic text only, Devanagari only, what the joiner and tag rules do and do not flag, the benchmark proves a narrow thing, nothing published, one wheel platform, nothing signed, CI not yet run on the Sprint 3 changes, target hardware unmeasured. The wheel and npm READMEs carry their own Limitations sections | D3 | no |
| 4 | Signed artifacts and manifest | Open | Owner must: `cargo run -p cp-sign -- keygen --out ./keys` offline, then sign `dist/release-manifest.json` with `cp-sign sign` (row 4 below). Tooling exists, signing does not. `scripts/release-manifest.mjs` writes an unsigned `airplanemode.manifest/0.1` listing the wheel and the npm tarball with their SHA-256 and size (tests: `tests/scripts/release-manifest.sh`, 42 checks, `red-D3-09.log` then `green-D3-09.log`; the script differs from pagetriage's only in two constants, `diff-release-manifest.log`). A dry run with the public RFC 8032 test key through `cp-sign` verified with `--allow-test-key` and was refused without it (`dry-run-sign.log`). That signature proves the tooling only: it is not a release signature, and no signed manifest or key is in this repository. A real key does not exist yet | owner, D6 (tooling) | yes |
| 5 | CHANGELOG and semver tag | Open | Owner must: after rows 1, 2, 4, 6, 7 are Done, `git tag v0.1.1 && git push origin v0.1.1` (tag procedure below). [CHANGELOG.md](../CHANGELOG.md) carries the Sprint 5 changes under `## [Unreleased]` (the architect dates them as `## [0.1.1] - 2026-11-18 (untagged)` at wrap-up) and, below them, the `## [0.1.0]` entry for Sprints 1 to 4, which was never tagged. The tag does not exist (`git tag` prints nothing) and must not be created until every row above and below is Done. The workspace version is 0.1.1 (`tests/scripts/release-doc.sh` checks that every crate, `Cargo.lock`, the wheel and the npm package.json carry the same one) | owner | yes |
| 6 | Package installable from a clean machine | Open (installs proven locally on macOS arm64; CI built the other platforms; nothing published) | Owner must: reserve the names, publish, then run the install commands of the "After the owner publishes" block (row 6 below) on a clean machine. Installed offline from locally built 0.1.1 artifacts on macOS arm64, each followed by a real call: the wheel `glyphsift-0.1.1-cp39-abi3-macosx_11_0_arm64.whl` (platform tag `macosx_11_0_arm64`, 254,147 bytes) into a `python3 -m venv` (`pip install --no-index --no-deps`) and into a `uv venv` (`uv pip install --offline --no-index --no-deps`), `score_ppm('कखग\ufffd')` printing 750000 and `gate()` answering (`evidence/sprint-5/D3/green/package-python.log`; the stubs pass `mypy --strict`); the tarball `airplanemode-glyphsift-0.1.1.tgz` (121,009 bytes) from `npm pack` into a fresh empty directory with an empty cache (`npm i <tgz> --ignore-scripts --offline`; `npm ls` shows one package), a Node call byte-equal to `glyphsift check` and to `glyphsift gate`, and a bundler-free page in installed Chrome with 0 console errors (`evidence/sprint-5/D3/green/package-npm.log`); the CLI with `cargo install --path crates/glyphsift-cli --locked` and every documented exit code on the installed binary, `gate` included (`evidence/sprint-5/D3/green/cli-install.log`); and the sdist `glyphsift-0.1.1.tar.gz` (110,435 bytes after fix round 2, which added three repository-root files the gate tests read; it carries the README as the core crate's README), whose `Cargo.lock` is pruned to its own workspace (61 entries to 36, same versions and checksums) so that `cargo build --locked` succeeds, and `cargo test --locked` passes, from the unpacked tree (S1-103 and BUG-T2-S5-12: `evidence/sprint-5/D3/green/D3-FIX1-package-sdist.log` and `tests/scripts/sdist-locked.sh`). The sizes and SHA-256 of all of them, with the toolchain versions, are in `evidence/sprint-5/D3/gates-s5.log`, the one log this row cites for artifact sizes. The wheel, the tarball, the sdist and each crate carry `LICENSE` and `NOTICE`, no test data in the wheel or the tarball, no lifecycle script and nothing over 5 MB. CI built 0.1.0 artifacts for three platforms at 5ff0c47 (see "First CI run of the wheels job" below); the 0.1.1 ones do not exist until CI builds them from the pushed commit. Not closed: nothing is published, the names are not reserved, no CI-built wheel has been installed on a machine other than its own runner, and no clean machine has installed from a registry | owner | yes |
| 7 | Short write-up | Open | Owner must: write and publish the write-up from the measured figures once row 2 has numbers (row 7 below). No write-up exists. It is written from the measured numbers once row 2 closes; the demo page at <https://airplanemode-labs.github.io/glyphsift/> is the natural home. Only a draft from existing evidence may precede the owner's tag and publish | owner | yes |

Blocker-for-tag rows Open today: 1, 2, 4, 5, 6, 7. Tagging v0.1.1 today would not be honest.

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
| T3-S5-03 and T3-S5-15: README and CHANGELOG throughput figures differ from the log they cite; the 8 GB column says only "not measured" | Fixed: every figure equals `evidence/sprint-5/D3/green/throughput.log` (gate 40 ms, validate 234, score_ppm 80, check 67, native gate 17) and every 8 GB cell reads "not measured on 8 GB" | `tests/scripts/readme-claims.sh` sections B and C |
| BUG-T1-S5-05 / T3-S5-04: the README's first Status line is not the status line the demo and `site/data/demos.json` carry | Fixed: the first line of the README's Status section is the status line verbatim, the narrative follows it | `tests/scripts/readme-claims.sh` section A |

## First CI run of the wheels job (read on 18 Nov 2026)

Run [43667702791](https://github.com/AirplaneMode-Labs/glyphsift/actions/runs/43667702791), workflow `ci`, push to `main`, head
`5ff0c47ec1fcb0b8d1c80f0029aa89ab78e03d2e`, started 2026-11-15T02:25:18Z, finished 02:29:43Z, conclusion `success`: all 14 jobs
green, the three `wheels` jobs, the `packaging` job and the `demo-browser` job among them, none of which had run before (the last earlier run
was the Sprint 2 commit). Read on 18 Nov 2026 with `gh run view 43667702791 --repo AirplaneMode-Labs/glyphsift --json status,conclusion,headSha,jobs`
and `gh run view ... --job <id> --log`, plus `gh api` GETs for the job ids and the artifact list; nothing was changed or re-run.
Job logs: `evidence/sprint-5/D3/ci/`.

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
- Nothing about reproducibility across machines. The same sources gave a macOS wheel of 247,045 bytes on the runner and 247,060 on this Mac (Sprint 4), and an npm tarball of 112,296 bytes on the runner and 112,744 locally. The
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
match, for no gain while nothing is published from a Mac. The Linux and Windows wheels have no such fields.

**The sdist is a source release and deliberately includes `crates/*/tests`** (TD-56; T3-S5-05). The sdist
carries seven test files, 111,928 bytes before compression in the 0.1.1 sdist (the Rust test sources and the 35,270-byte synthetic case
table `crates/glyphsift-core/tests/cases/devanagari.toml`), and it ships three repository-root files the gate tests read, at the same relative paths:
`bench/corpus/clean.txt`, `docs/gate.md` and `docs/score-vs-noise.csv` (BUG-T2-S5-12; all three are synthetic and own-authored;
maturin cannot include a path outside the Python project, so `scripts/add-sdist-files.py` appends them). A person who
receives the sdist can therefore run `cargo test --locked` and see the 154-case table and the gate tests pass without
cloning the repository: `tests/scripts/sdist-locked.sh` runs `cargo test --locked --no-fail-fast -p glyphsift-core` in the
unpacked sdist and requires 0 failed with no `--skip` (before the fix 3 of 14 gate tests failed). No file in it is
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
2. On Windows only, on the text as typed: no `\\?\` or `\\.\` prefix; no UNC path (`\\server\share`, also `//server/share` and the
   admin share of the local drive); no drive-relative path (`C:name`, `C:dir\name`, `C:`), whose meaning depends on a per-drive
   working directory; no `:` after the drive (an alternate data stream); no reserved device name (`CON PRN AUX NUL COM1-9 LPT1-9
   CONIN$ CONOUT$`, any case, with or without an extension); no component ending in `.` or a space (Windows strips them); no
   character Windows forbids in a file name.
3. `dist/` and the deepest existing ancestor of `--out` are resolved with `fs.realpathSync.native`: on Windows that expands 8.3 short
   names, gives each name its on-disk case and follows every symlink and junction, including a reparse point that `lstat` does not
   report as a link; on a case-insensitive macOS volume it gives `DIST/` the on-disk case `dist/`, which is why a differently-cased
   spelling is accepted there. A dangling link on the way is refused.
4. If `--out` itself exists it must be a regular file. A symbolic link or junction is refused whatever it points at (a file inside
   `dist/` included), and so is a directory, a FIFO, a socket or a device. A regular file or a dangling link at `dist/` itself is
   a one-line refusal.
5. Containment: `relative(distReal, final)` must be non-empty, not absolute (another drive) and not `..` or `..` plus a separator;
   a file called `..foo` is fine. Elsewhere than Windows the comparison is exact, so a difference in spelling can refuse a path
   but never accept one.
6. The bytes go to a temporary name (`.release-manifest-<random>.tmp`) opened with the `wx` flag inside the resolved parent, are
   flushed and are renamed over the target, after the parent has been resolved and checked a second time. `rename` replaces a
   link at the target instead of following it, and replaces a hard link's name without opening its inode: a file in `dist/` that is a
   second name (a hard link) of a file outside `dist/` is replaced by the manifest and the outside file keeps its bytes (T2's R34;
   the Sprint 5 script wrote through it with `writeFileSync`).

What is not closed: between the second check and the `rename` another process that can already write inside `dist/` could replace a
directory by a link. This is a local tool run by the owner on their own checkout, so that process would have to be the owner's own
account; the window is narrowed, not removed. `dist/` itself may be a link (the check is relative to what it resolves to). On a
case-sensitive volume a differently-cased spelling of `dist/` is another directory and is refused.

How the Windows rules are proven here and where they are not. This Mac cannot run Windows. On macOS the same files give 36 unit
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
| `tests/python/check_wheel.py` passes on the `manylinux_2_17` and `win_amd64` wheels | no Linux or Windows machine; the script is platform independent (it reads the zip) and passes on the macOS wheel |
| the `doc` job (`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked`) is green on `ubuntu-latest` | passes locally on macOS with the same flags |
| the gate determinism leg (200 cases, `scripts/determinism.sh`) is byte-identical on Ubuntu, macOS and Windows, including `isWellFormed` in Node 22 | this Mac only; Windows runs the corpus through Git Bash and `glyphsift.exe` |
| the demo's Gate tab passes `tests/demo/check_demo.mjs` (234 checks) in the runner's Chrome | passes in installed Chrome on this Mac |
| glyphsift check (windows-latest) proves the ported `--out` containment: `confine.test.mjs` (36 tests, none skipped) and `release-manifest.sh` with native symlinks asserted by `[ -L ]`, hard links, and a real junction made with MSYS conversion off | this Mac cannot run Windows; macOS ran the same two files (36 tests, 68 checks, 0 skipped) and reproduced the differently-cased `dist/` refusal, the write-through and the stack traces against the old script |
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

Each Open row, with the commands. Run them from a checkout of `AirplaneMode-Labs/glyphsift` (`cp-sign` comes
from the private `AirplaneMode-Labs/control-plane`).

**Row 1, after the push.**

Owner must: review the Sprint 5 commits, `git push` (the order for all seven repositories is in the sprint report), then read the CI run for the pushed
commit on `ubuntu-latest`, `macos-latest` and `windows-latest`, and the Linux-only `doc`, `packaging` and `demo-browser` jobs (the `wheels` job
now also runs the sdist `--locked` build and the wheel contents check):

```sh
gh run list --repo AirplaneMode-Labs/glyphsift --limit 5
gh run view <run-id> --repo AirplaneMode-Labs/glyphsift --json jobs --jq '.jobs[] | [.name, .conclusion] | @tsv'
```

Read these legs by name (one line per leg): **glyphsift check (windows-latest) proves the ported containment** (its step "Release-manifest --out
containment" runs `confine.test.mjs` and `release-manifest.sh`; a red here that names "could not create a symlink" or "could not create a junction"
means the runner cannot make links, not that the code is wrong, and is still a red); **glyphsift packaging (ubuntu-latest)** runs
`tests/scripts/ci-policy.sh` section J, which fails if `cargo doc` prints "collision" (cargo's own warning, which `-D warnings` on rustdoc does not
turn into a failure), next to the `doc` job (rustdoc, warnings are errors); **glyphsift determinism (ubuntu, macos, windows)** proves the gate
corpus is byte-identical on all three.

Change row 1's status to Done only when every job is green for the commit that will be tagged. The `doc` job, the sdist step and the wheel
contents check are new in Sprint 5 and have never run in CI: if one fails, the fix goes in `.github/workflows/ci.yml` or the scripts, not in this table.

**Row 2, benchmark on the 8 GB Windows no-GPU laptop.**

Owner must: run the steps below on the target machine itself (8 GB RAM, no discrete GPU, a current Windows 10 or 11,
Chrome) and write down what the commands print. Invent nothing. The throughput script is `scripts/throughput.mjs`
(`node scripts/throughput.mjs corpus-1mib.txt --cli target\release\glyphsift.exe`).

1. Record the machine: Windows version (`winver`), CPU model, RAM, whether a GPU is present
   (`Get-CimInstance Win32_VideoController`), Chrome version, and that Wi-Fi is off for the browser run.
2. Build the CLI and make the 1 MiB text (the corpus repeated line by line up to 1,048,576 bytes, as in
   `evidence/sprint-3/D3/throughput.log`), then time it five times:

   ```sh
   cargo build --release -p glyphsift-cli
   node -e 'const fs=require("fs");const L=fs.readFileSync("bench/corpus/clean.txt","utf8").split("\n").filter((x,i,a)=>!(i===a.length-1&&x===""));let out="",bytes=0,i=0;for(;;){const l=L[i%L.length]+"\n";const n=Buffer.byteLength(l);if(bytes+n>1048576)break;out+=l;bytes+=n;i++}fs.writeFileSync("corpus-1mib.txt",out);console.log(i,"lines",bytes,"bytes")'
   ```

   Then, in PowerShell, five timings: `1..5 | ForEach-Object { (Measure-Command { .\target\release\glyphsift.exe check corpus-1mib.txt | Out-Null }).TotalMilliseconds }`.
   (The Node line was run on the Mac and gives the 12,888 lines and 1,048,569 bytes of `throughput.log`; the PowerShell line
   was not run, there is no PowerShell here.)
3. WebAssembly: `scripts/install-wasm-tools.sh`, `scripts/build-wasm.sh` (Git Bash), then in Node
   `node tests/determinism/run_wasm.mjs` for correctness and your own `performance.now()` loop around
   `validate()` and `score_ppm()` from `dist/wasm/nodejs`, best of five; `node scripts/throughput.mjs corpus-1mib.txt` does exactly that
   and also times the native CLI.
4. Browser: `scripts/build-demo.sh`, serve `demo/dist` under `/glyphsift/` (this does it and prints the 1 MiB time:
   `npm ci --prefix tools/playwright --ignore-scripts`, then
   `PLAYWRIGHT_DIR=$PWD/tools/playwright node tests/demo/check_demo.mjs --cli target/release/glyphsift`), turn Wi-Fi off, open it in Chrome, load a synthetic `.txt` file and note the time.
5. Peak memory: Task Manager, Details tab, "Peak working set (memory)" for the Chrome tab process, and for
   `glyphsift.exe` during the timing run. Write the figure and where it came from.
6. Put the results in the README Benchmarks table (the "8 GB Windows no-GPU laptop" column), cite where the raw
   output is kept, and change row 2 to Done here.

**Row 4, signed artifacts and manifest.**

Owner must: on the offline key machine (not this Mac, not CI), generate the real key and sign the manifest:

```sh
git clone https://github.com/AirplaneMode-Labs/control-plane && cd control-plane   # private repo
cargo run -p cp-sign -- keygen --out ./keys            # key.secret stays on this machine, mode 0600
cargo run -p cp-sign -- keyid --pub ./keys/key.pub     # record the keyId in the release notes
```

Then, after the artifacts exist (rows 5 and 6 steps), in the glyphsift checkout:

```sh
scripts/build-wasm.sh && scripts/package-npm.sh          # dist/npm/airplanemode-glyphsift-0.1.1.tgz
scripts/package-python.sh    # maturin@1.16.0 pinned, builder paths remapped; the wheel lands in dist/wheels
SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) node scripts/release-manifest.mjs --out dist/release-manifest.json \
  dist/npm/airplanemode-glyphsift-0.1.1.tgz dist/wheels/glyphsift-0.1.1-*.whl
cargo run -p cp-sign -- sign --key ./keys/key.secret dist/release-manifest.json --out dist/release-manifest.signed.json
cargo run -p cp-sign -- verify --pub ./keys/key.pub dist/release-manifest.signed.json
shasum -a 256 dist/npm/*.tgz dist/wheels/*.whl     # each value must equal the manifest's sha256 for that file
```

Publish `release-manifest.signed.json` and `key.pub` next to the artifacts ([RELEASING.md](RELEASING.md),
"Signing the manifest"). Never use `--allow-test-key` for a release.

**Row 5, CHANGELOG and semver tag.**

Owner must: once rows 1, 2, 4, 6 and 7 are Done and CI is green on the tag commit, follow the tag procedure below
from step 1, ending with `git tag v0.1.1` (the owner only) and `git push origin v0.1.1`.

**Row 6, installable from a clean machine.**

Owner must: reserve the names, build and publish, then prove the install from a registry on a clean machine.

1. Reserve the names (due 22 Nov 2026): npm scope `@airplanemode` (package `@airplanemode/glyphsift`), PyPI `glyphsift`,
   crates.io `glyphsift-core` and `glyphsift-cli`.
2. Build wheels for Linux, macOS and Windows: after the push, the `wheels` job of `ci.yml` builds them (manylinux_2_17
   through zig on Ubuntu, `win_amd64` on Windows, macOS arm64) and an sdist, with tools pinned by hash, and keeps them as a
   workflow artifact for 7 days (`gh run download <run-id> --repo AirplaneMode-Labs/glyphsift -n glyphsift-wheels-ubuntu-latest`
   and the same for `windows-latest` and `macos-latest`). Read the job first (see "CI-only proofs"). Before publishing those
   wheels, change the OS classifiers in `crates/glyphsift-py/pyproject.toml` from MacOS alone to include
   `Operating System :: POSIX :: Linux` and `Operating System :: Microsoft :: Windows`, and update the matching assertion in
   `tests/python/check_wheel.py` in the same commit, so the metadata does not claim a platform that was not proven. Then
   publish per tag-procedure steps 4 to 6 below.
3. On a machine that has never seen this repository, with Wi-Fi on, run the commands in the block below and record the
   output. They are registry commands and work only after publishing.

   **After the owner publishes**

   ```sh
   python3 -m venv v && v/bin/pip install glyphsift==0.1.1 && v/bin/python -I -c "import glyphsift; print(glyphsift.score_ppm('कखग\ufffd'))"
   mkdir t && cd t && npm init -y && npm i @airplanemode/glyphsift@0.1.1 && node -e 'console.log(require("@airplanemode/glyphsift").score_ppm("कखग\ufffd"))'
   cargo install glyphsift-cli && glyphsift --version
   ```

4. Change the README Install section so the "After the owner publishes" commands move into the main text, and
   mark row 6 Done with the recorded output as evidence.

**Row 7, short write-up.**

Owner must: once row 2 has numbers, write the short write-up from the measured figures, each with its evidence path,
publish it (the demo page is the natural home), and mark row 7 Done.

## Tag procedure (owner only, in this order)

Taken from [RELEASING.md](RELEASING.md); do not start it while any Blocker-for-tag row is Open.

1. **Date the release.** In `CHANGELOG.md` change `## [0.1.1] - 2026-11-18 (untagged)` to
   `## [0.1.1] - YYYY-MM-DD`. The workspace version is already 0.1.1 (`Cargo.toml`, `[workspace.package]`); the
   wheel and the npm package take it from there. This is the tag commit; nothing else goes in it.
2. **Run the gate** on that commit: `cargo fmt --all --check`, `cargo clippy --workspace --all-targets --locked -- -D warnings`,
   `cargo test --locked`, `scripts/determinism.sh`, `scripts/package-python.sh`, `scripts/package-npm.sh`,
   `tests/scripts/run-all.sh`. CI must be green on Linux, macOS and Windows for the commit, the `wheels` job included.
3. **Tag** `v0.1.1` on that commit and push the tag.
4. **crates.io.** `cargo publish -p glyphsift-core`, then (once the index has it) `cargo publish -p glyphsift-cli`.
5. **PyPI.** Upload the wheels for every platform: `twine upload dist/wheels/*`.
6. **npm.** `npm publish dist/npm/airplanemode-glyphsift-0.1.1.tgz --access public`.
7. **Sign.** Write the manifest (`node scripts/release-manifest.mjs --out dist/release-manifest.json <artifacts>`), sign it
   with `cp-sign` and the real key on the offline key machine (see "Owner must", row 4), and publish the signed
   manifest with the release.
8. **Demo and write-up.** The `pages` workflow deploys the demo on the push; publish the write-up.

Do not tag until every Blocker-for-tag row is Done.

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
