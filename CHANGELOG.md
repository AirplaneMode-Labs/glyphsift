# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- GitHub Pages demo at <https://airplanemode-labs.github.io/glyphsift/> (`demo/`, assembled by
  `scripts/build-demo.sh`, deployed by `.github/workflows/pages.yml`, built again by the CI `demo`
  job): grapheme clusters of pasted Devanagari with code points and byte ranges, three synthetic
  samples, the `validate()` Unimplemented error shown verbatim, the sixteen rule names marked "not
  yet checked", and a "What this demo does not do yet" box.
- WASM exports `clusters_json()`, `issue_kinds()` and `report_spec()` next to `validate()`,
  `clusters()` and `version()`; the wasm crate now uses the workspace `serde_json` (no
  `preserve_order`) instead of a hand-rolled array serialiser.
- `scripts/install-wasm-tools.sh`: installs wasm-bindgen 0.2.129 and binaryen 133 from official
  release tarballs, comparing each against a SHA-256 digest pinned in the script.
- `persist-credentials: false` on every `actions/checkout` in CI.
- Cargo workspace (resolver 3) with `glyphsift-core`, `glyphsift-cli`, `glyphsift-py` (PyO3 0.30,
  abi3-py39, maturin) and `glyphsift-wasm` (wasm-bindgen 0.2.129); rust-toolchain 1.98, edition 2024.
- Report types `Report`, `Cluster`, `Issue`, `IssueKind` (sixteen Devanagari rules) with the
  canonical compact-JSON rule, and `validate()` returning `Error::Unimplemented { since: "Sprint 2" }`.
- `clusters()`: UAX #29 extended grapheme clusters with byte offsets (unicode-segmentation 1.13).
- CLI `glyphsift check <file|->` (exit 0 report, 2 input error, 3 unimplemented).
- Tests-first case table `crates/glyphsift-core/tests/cases/devanagari.toml` (77 cases) with a
  harness `#[ignore = "Sprint 2: validator not implemented"]` and non-ignored checks that the
  table parses, covers every `IssueKind` and matches the segmenter.
- `docs/devanagari-rules.md` (code-point tables, cluster grammar, rule definitions, public API) and
  `docs/corruption-generator.md` (noise families, schedule, evaluation protocol, CLI shape).
- `deny.toml` licence policy, `clippy.toml` determinism rules (no HashMap/HashSet, no platform libm),
  `scripts/build-wasm.sh`.
- CI on ubuntu, macos and windows: fmt, clippy, test, wasm32 checks, PyO3 check, licence sweep;
  actions pinned by SHA; Dependabot for cargo and github-actions.
- LICENSE (Apache-2.0), NOTICE, README with Limitations, CONTRIBUTING, SECURITY.

### Fixed

- `crates/glyphsift-py` now carries the `README.md`, `LICENSE` and `NOTICE` files its
  `pyproject.toml` names, so `uvx maturin build --release` produces the cp39-abi3 wheel (it failed
  with "Failed to read readme specified in pyproject.toml").

### Dependencies

- `serde`, `serde_json` (no `preserve_order`), `thiserror`, `unicode-segmentation` in the core;
  `clap` in the CLI; `toml` as a dev-dependency to read the case table. All permissively licensed.
