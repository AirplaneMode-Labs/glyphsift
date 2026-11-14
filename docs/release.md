# Release checklist

One row per item of the definition of done that every Airplane Mode Labs release must meet. A row is
Done only when the Evidence column names a file or command that proves it today; anything else is
Open. Nothing may be tagged while a Blocker-for-tag row is Open. The release is 0.1.0, a release
candidate: the workspace version is already 0.1.0, the notes live under `## [0.1.0] - UNRELEASED
(release candidate, not tagged)` in [CHANGELOG.md](../CHANGELOG.md), and the tag commit (step 1 below) only
changes that heading to a date.

Status as of 2026-11-14 (Sprint 3). Evidence paths under `evidence/sprint-3/D3/` are copied there from the
Sprint 3 scratch folder by the architect at wrap-up. Nothing is published, signed or tagged, and the npm scope
`@airplanemode` and the PyPI and crates.io names `glyphsift`, `glyphsift-core` and `glyphsift-cli` are not reserved.

| # | Definition-of-done item | Status | Evidence | Owner | Blocker-for-tag |
|---|---|---|---|---|---|
| 1 | Tests written before the implementation; CI green on Linux, macOS and Windows | Tests-first evidence Done (red/green logs); local macOS green; CI on three OSes configured, pending the owner's push | Owner must: `git push`, then `gh run list --repo AirplaneMode-Labs/glyphsift --limit 5` and read every job (commands under "Owner must", row 1). Tests first, each with its red log before its green log in `evidence/sprint-3/D3/`: the case table (`red-D3-01.log` then `green-D3-01.log`, `red-D3-02.log` and `red-D3-02-final-cases-old-rules.log` then `green-D3-02.log`; 32 of the 54 new cases failed first), the wheel (`red-D3-04.log`, `green-D3-04.log`), the npm package (`red-D3-05.log`, `green-D3-05.log`), the CLI surface (`red-D3-06.log`, `green-D3-06.log`), the demo (`red-D3-07.log`, `green-D3-07.log`) and the release-manifest tool (`red-D3-09.log`, `green-D3-09.log`). Local macOS arm64: `cargo fmt`, `clippy -D warnings`, `cargo test`, `scripts/determinism.sh` (native, Python and WASM byte-identical on 13 samples) and `cargo deny check bans licenses sources` pass (`gates-s3.log`). The three-OS matrix (`check`, `determinism`, `deny`, `demo`, plus the new `packaging` and `demo-browser` jobs) is configured in `.github/workflows/ci.yml`. Its last run, on the Sprint 2 commit `19ce773` on 9 Nov 2026, was green on `ubuntu-latest`, `macos-latest` and `windows-latest` for all 9 jobs ([run](https://github.com/AirplaneMode-Labs/glyphsift/actions/runs/42635283936)); the Sprint 3 changes have not been pushed, so no CI run covers them. Not marked Done until the owner pushes and reads CI | D3, then owner (push, read CI) | yes |
| 2 | Benchmark on an 8 GB laptop recorded in the README | Open | Owner must: run `node scripts/throughput.mjs corpus-1mib.txt --cli target/release/glyphsift` and the browser run on the 8 GB Windows no-GPU laptop (steps under "Owner must", row 2). README [Benchmarks](../README.md#benchmarks) carries Apple-silicon figures (`evidence/sprint-3/D3/throughput.log`, from `scripts/throughput.mjs`) next to an "8 GB Windows no-GPU laptop" column that reads "not measured". No figure for that machine exists and none was invented. The procedure is below | owner | yes |
| 3 | README limitations section | Done | README [Limitations](../README.md#limitations): structural checks only, synthetic text only, Devanagari only, what the joiner and tag rules do and do not flag, the benchmark proves a narrow thing, nothing published, one wheel platform, nothing signed, CI not yet run on the Sprint 3 changes, target hardware unmeasured. The wheel and npm READMEs carry their own Limitations sections | D3 | no |
| 4 | Signed artifacts and manifest | Open | Owner must: `cargo run -p cp-sign -- keygen --out ./keys` offline, then sign `dist/release-manifest.json` with `cp-sign sign` (row 4 below). Tooling exists, signing does not. `scripts/release-manifest.mjs` writes an unsigned `airplanemode.manifest/0.1` listing the wheel and the npm tarball with their SHA-256 and size (tests: `tests/scripts/release-manifest.sh`, 42 checks, `red-D3-09.log` then `green-D3-09.log`; the script differs from pagetriage's only in two constants, `diff-release-manifest.log`). A dry run with the public RFC 8032 test key through `cp-sign` verified with `--allow-test-key` and was refused without it (`dry-run-sign.log`). That signature proves the tooling only: it is not a release signature, and no signed manifest or key is in this repository. A real key does not exist yet | owner, D6 (tooling) | yes |
| 5 | CHANGELOG and semver tag | Open | Owner must: after rows 1, 2, 4, 6, 7 are Done, `git tag v0.1.0 && git push origin v0.1.0` (tag procedure below). [CHANGELOG.md](../CHANGELOG.md) has `## [0.1.0] - UNRELEASED (release candidate, not tagged)` with every Sprint 1 to 3 change and finding id. The tag does not exist (`git tag` prints nothing) and must not be created until every row above and below is Done. The workspace version is already 0.1.0 | owner | yes |
| 6 | Package installable from a clean machine | Open (installs proven locally on macOS arm64; nothing published) | Owner must: reserve the names, publish, then run the install commands of the "After the owner publishes" block (row 6 below) on a clean machine. Installed offline from locally built artifacts on macOS arm64, each followed by a real call: the wheel `glyphsift-0.1.0-cp39-abi3-macosx_11_0_arm64.whl` (platform tag `macosx_11_0_arm64`) into a `python3 -m venv` (`pip install --no-index --no-deps`) and into a `uv venv` (`uv pip install --offline --no-index --no-deps`), `score_ppm('कखग\ufffd')` printing 750000 (`evidence/sprint-3/D3/install-wheel-r2.log`, 245,869 bytes, sha256 8bb915cf...; the stubs pass `mypy --strict`); the tarball `airplanemode-glyphsift-0.1.0.tgz` from `npm pack` into a fresh empty directory with an empty cache (`npm i <tgz> --ignore-scripts --offline`; `npm ls` shows one package), a Node call byte-equal to `glyphsift check`, and a bundler-free page in installed Chrome with 0 console errors (`evidence/sprint-3/D3/npm-install-r2.log`, 111,710 bytes, sha256 de2efaef...); the CLI with `cargo install --path crates/glyphsift-cli --locked` and every documented exit code on the installed binary (`evidence/sprint-3/D3/cli-install-r2.log`). The wheel, the tarball and each crate carry `LICENSE` and `NOTICE`, no test data, no lifecycle script and nothing over 5 MB. Not closed: nothing is published, the names are not reserved, only the macOS arm64 wheel exists (Linux and Windows wheels and an sdist are not built; Sprint 4 carry-over), and no clean machine has installed from a registry | owner | yes |
| 7 | Short write-up | Open | Owner must: write and publish the write-up from the measured figures once row 2 has numbers (row 7 below). No write-up exists. It is written from the measured numbers once row 2 closes; the demo page at <https://airplanemode-labs.github.io/glyphsift/> is the natural home. Only a draft from existing evidence may precede the owner's tag and publish | owner | yes |

Blocker-for-tag rows Open today: 1, 2, 4, 5, 6, 7. Tagging v0.1.0 today would not be honest.

## Owner must

Each Open row, with the commands. Run them from a checkout of `AirplaneMode-Labs/glyphsift` (`cp-sign` comes
from the private `AirplaneMode-Labs/control-plane`).

**Row 1, after the push.**

Owner must: review the Sprint 3 commits, `git push`, then read the CI run for the pushed commit on `ubuntu-latest`,
`macos-latest` and `windows-latest`, and the Linux-only `packaging` and `demo-browser` jobs:

```sh
gh run list --repo AirplaneMode-Labs/glyphsift --limit 5
gh run view <run-id> --repo AirplaneMode-Labs/glyphsift --json jobs --jq '.jobs[] | [.name, .conclusion] | @tsv'
```

Change row 1's status to Done only when every job is green. `packaging` and `demo-browser` have never run: if they
fail, the fix goes in `.github/workflows/ci.yml` or the scripts, not in this table.

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
   `mkdir pw && cd pw && npm init -y && npm i playwright@1.65.0 --ignore-scripts && cd ..`, then
   `PLAYWRIGHT_DIR=$PWD/pw node tests/demo/check_demo.mjs --cli target/release/glyphsift`), turn Wi-Fi off, open it in Chrome, load a synthetic `.txt` file and note the time.
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
scripts/build-wasm.sh && scripts/package-npm.sh          # dist/npm/airplanemode-glyphsift-0.1.0.tgz
scripts/package-python.sh    # maturin@1.16.0 pinned, builder paths remapped; the wheel lands in dist/wheels
SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) node scripts/release-manifest.mjs --out dist/release-manifest.json \
  dist/npm/airplanemode-glyphsift-0.1.0.tgz dist/wheels/glyphsift-0.1.0-*.whl
cargo run -p cp-sign -- sign --key ./keys/key.secret dist/release-manifest.json --out dist/release-manifest.signed.json
cargo run -p cp-sign -- verify --pub ./keys/key.pub dist/release-manifest.signed.json
shasum -a 256 dist/npm/*.tgz dist/wheels/*.whl     # each value must equal the manifest's sha256 for that file
```

Publish `release-manifest.signed.json` and `key.pub` next to the artifacts ([RELEASING.md](RELEASING.md),
"Signing the manifest"). Never use `--allow-test-key` for a release.

**Row 5, CHANGELOG and semver tag.**

Owner must: once rows 1, 2, 4, 6 and 7 are Done and CI is green on the tag commit, follow the tag procedure below
from step 1, ending with `git tag v0.1.0` (the owner only) and `git push origin v0.1.0`.

**Row 6, installable from a clean machine.**

Owner must: reserve the names, build and publish, then prove the install from a registry on a clean machine.

1. Reserve the names (due 22 Nov 2026): npm scope `@airplanemode` (package `@airplanemode/glyphsift`), PyPI `glyphsift`,
   crates.io `glyphsift-core` and `glyphsift-cli`.
2. Build wheels for Linux, macOS and Windows (a Sprint 4 carry-over: `maturin-action` in CI or a manylinux
   container), then publish per tag-procedure steps 4 to 6 below.
3. On a machine that has never seen this repository, with Wi-Fi on, run the commands in the block below and record the
   output. They are registry commands and work only after publishing.

   **After the owner publishes**

   ```sh
   python3 -m venv v && v/bin/pip install glyphsift==0.1.0 && v/bin/python -I -c "import glyphsift; print(glyphsift.score_ppm('कखग\ufffd'))"
   mkdir t && cd t && npm init -y && npm i @airplanemode/glyphsift@0.1.0 && node -e 'console.log(require("@airplanemode/glyphsift").score_ppm("कखग\ufffd"))'
   cargo install glyphsift-cli && glyphsift --version
   ```

4. Change the README Install section so the "After the owner publishes" commands move into the main text, and
   mark row 6 Done with the recorded output as evidence.

**Row 7, short write-up.**

Owner must: once row 2 has numbers, write the short write-up from the measured figures, each with its evidence path,
publish it (the demo page is the natural home), and mark row 7 Done.

## Tag procedure (owner only, in this order)

Taken from [RELEASING.md](RELEASING.md); do not start it while any Blocker-for-tag row is Open.

1. **Date the release.** In `CHANGELOG.md` change `## [0.1.0] - UNRELEASED (release candidate, not tagged)` to
   `## [0.1.0] - YYYY-MM-DD`. The workspace version is already 0.1.0 (`Cargo.toml`, `[workspace.package]`); the
   wheel and the npm package take it from there. This is the tag commit; nothing else goes in it.
2. **Run the gate** on that commit: `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`,
   `cargo test`, `scripts/determinism.sh`, `scripts/package-python.sh`, `scripts/package-npm.sh`,
   `tests/scripts/release-manifest.sh`. CI must be green on Linux, macOS and Windows for the commit.
3. **Tag** `v0.1.0` on that commit and push the tag.
4. **crates.io.** `cargo publish -p glyphsift-core`, then (once the index has it) `cargo publish -p glyphsift-cli`.
5. **PyPI.** Upload the wheels for every platform: `twine upload dist/wheels/*`.
6. **npm.** `npm publish dist/npm/airplanemode-glyphsift-0.1.0.tgz --access public`.
7. **Sign.** Write the manifest (`node scripts/release-manifest.mjs --out dist/release-manifest.json <artifacts>`), sign it
   with `cp-sign` and the real key on the offline key machine (see "Owner must", row 4), and publish the signed
   manifest with the release.
8. **Demo and write-up.** The `pages` workflow deploys the demo on the push; publish the write-up.

Do not tag until every Blocker-for-tag row is Done.
