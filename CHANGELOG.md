# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

Nothing yet.

## [0.1.0] - UNRELEASED (release candidate, not tagged)

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
