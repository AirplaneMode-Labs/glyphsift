# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

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

- Documented, not changed: `zwj_zwnj_misplaced` has no script condition, so joiners inside emoji sequences and
  Arabic-script words are flagged (weight 200). `docs/devanagari-rules.md` section 2 and the README Limitations now
  say so; no rule, weight, corpus or bench output changed. Planned for glyphsift v0.1 (Sprint 3): restrict the
  rule to Devanagari bases, table cases first. BUG-T2-S2-07
- Documented, not changed: invisible Extend characters (Unicode tag characters `U+E0001`, `U+E0020` to `U+E007F`,
  and non-Indic combining marks such as `U+0301`) attached to a Devanagari base are not flagged, so a line
  containing them can score clean. `docs/devanagari-rules.md` section 2 and the README Limitations say so.
  Planned for glyphsift v0.1 (Sprint 3): flag tag characters and non-Indic combining marks in Devanagari
  clusters, table cases first (BUG-T2-S2-15)

- Weights file and corpus: the SHA-256 of `crates/glyphsift-core/weights/devanagari.toml` and `bench/corpus/clean.txt`
  was logged before the first `glyphsift bench` run and neither file has changed since; a later change to either
  is listed here with its reason.
- Mid-run correction, not a weights or corpus change: the `legacy_font` generator moved the short-i matra at
  sites where the previous cluster was not a word boundary although it had declared those sites ineligible
  (recall 20/24 in a test before the first bench run); the sites now agree. D3-03

### Fixed

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

### Dependencies

- `serde`, `serde_json` (no `preserve_order`), `thiserror`, `unicode-segmentation` and (Sprint 2)
  `unicode-general-category` in the core; `clap` in the CLI; `toml` as a dev-dependency to read the case
  table and the weights file in tests. All permissively licensed; `cargo deny` accepts the tree.
