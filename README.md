# glyphsift

Scores whether extracted Indic text is clean enough to trust or train on: a deterministic
Devanagari grapheme-cluster validator with a Rust core, a WASM build for the browser, a Python
wheel and a thin CLI.

Part of [Airplane Mode Labs](https://github.com/AirplaneMode-Labs), an open-core, offline-first,
browser-native AI infrastructure lab. Package names use the placeholder scope `@airplanemode` /
crate names `glyphsift` until the handles are reserved; nothing is published yet.

## Status

Skeleton; validator lands in Sprint 2 (23 Nov to 6 Dec 2026).

What exists today:

- the Cargo workspace (`glyphsift-core`, `glyphsift-cli`, `glyphsift-py`, `glyphsift-wasm`) that
  builds on Linux, macOS and Windows, for `wasm32-unknown-unknown` and as a PyO3 extension;
- the report types (`Report`, `Cluster`, `Issue`, `IssueKind`) and the canonical JSON rule;
- `validate(text)` returning `Err(Error::Unimplemented { since: "Sprint 2" })`;
- `clusters(text)`: UAX #29 extended grapheme clusters with byte offsets (this part is real);
- the tests-first case table `crates/glyphsift-core/tests/cases/devanagari.toml` (77 cases, every
  `IssueKind` covered) and its harness, `#[ignore]`d until the validator exists;
- the rules the validator will implement: [docs/devanagari-rules.md](docs/devanagari-rules.md);
- the design for the corruption generator that produces the Sprint 2 score-versus-noise chart:
  [docs/corruption-generator.md](docs/corruption-generator.md).

## Demo

Live demo: <https://airplanemode-labs.github.io/glyphsift/>. Built from `main` by
`.github/workflows/pages.yml` on every push; it shows only what works today and has a box titled
"What this demo does not do yet". It runs entirely in the browser: no upload, no analytics, no
third-party scripts or fonts.

What it shows: a textarea for pasted Devanagari or Hindi text with three synthetic samples (clean,
OCR-corrupted, legacy-font gibberish), the UAX #29 grapheme clusters the WASM build computes
(`clusters_json()`: cluster text, code points, byte range), the `Unimplemented` error that
`validate()` throws in Sprint 1 shown verbatim next to the CLI's `{"error":"unimplemented","since":"Sprint 2"}`,
the sixteen rule names from `issue_kinds()` each marked "not yet checked", `report_spec()` and
`version()`. The defect-named samples say plainly that glyphsift does not detect those problems yet.
Sources in `demo/`; `scripts/build-demo.sh` assembles `demo/dist/` (git-ignored).

## Install

Nothing is published. From a clone:

```sh
cargo build --release            # core + CLI -> target/release/glyphsift
scripts/build-wasm.sh            # dist/wasm/{web,nodejs}; needs wasm-bindgen 0.2.129 and wasm-opt
scripts/install-wasm-tools.sh    # installs both from digest-pinned release binaries (default ~/.local/glyphsift-tools)
scripts/build-demo.sh            # demo/dist/: the GitHub Pages demo (runs build-wasm.sh first)
uvx maturin build --release -m crates/glyphsift-py/Cargo.toml -o target/wheels   # cp39-abi3 wheel
```

## Quick start

```sh
echo 'नमस्ते।' | cargo run -q -p glyphsift-cli -- check -
# Sprint 1 output, exit code 3:
# {"error":"unimplemented","since":"Sprint 2"}
```

From Sprint 2 the same command prints the canonical JSON report (see "How it works") and exits 0.
Exit codes: 0 report written, 2 input error (unreadable file or invalid UTF-8), 3 not implemented.

Python (after `maturin develop`): `glyphsift.validate(text)` returns the JSON string and raises
`NotImplementedError` in Sprint 1; `glyphsift.clusters(text)` works today.

Browser/Node (after `scripts/build-wasm.sh`): `validate(text)` throws until Sprint 2; `clusters(text)`,
`clusters_json(text)`, `issue_kinds()`, `report_spec()` and `version()` work today.

## How it works

1. Text is split into UAX #29 extended grapheme clusters (unicode-segmentation 1.13.x, including the
   Unicode 15.1 GB9c conjunct rule, so `क्ष` is one cluster).
2. Each cluster is matched against the Devanagari cluster grammar
   `(C nukta? virama (ZWJ|ZWNJ)?)* C nukta? matra? (anusvara|chandrabindu)? visarga?` and its
   alternatives for independent vowels and standalone signs; every deviation is one `Issue` with a
   stable `IssueKind` name (sixteen rules, listed in `docs/devanagari-rules.md`).
3. The report is serialised as compact JSON with fields in declaration order and no floats, so the
   native, Python and WASM builds emit byte-identical output for the same input.

Determinism is enforced by `clippy.toml`: no `HashMap`/`HashSet`, no platform `libm`; the core has
no clock, environment or file-system access.

## Contracts

glyphsift consumes no runtime/spec contract in Sprint 1. From Sprint 3 its WASM build will emit
`airplanemode.event/0.1` events through the runtime `EventSink` for timings only; the text being
scored never leaves the process.

## Benchmarks

| Scenario | Apple-silicon development machine | 8 GB Windows no-GPU laptop |
| --- | --- | --- |
| 10k clusters validated (native) | not measured | not measured |
| 10k clusters validated (WASM, Chrome) | not measured | not measured |
| Score versus noise (corruption benchmark) | not measured | not measured |

Figures appear here only when produced by a named command in a recorded run.

## Limitations

- Nothing validates yet: `validate()` returns `Unimplemented` on every input until Sprint 2.
- Devanagari only is planned for 0.1; Tamil and Bengali come later, after the design has proved
  language-agnostic.
- No dictionary and no language model: the validator checks orthographic structure, not whether a
  word exists. A well-formed nonsense word scores clean.
- Clusters are judged in isolation. Word- and document-level signals (legacy-font detection,
  Latin-gibberish ratio, repeated-cluster runs) are a Sprint 2 follow-up.
- No normalisation is applied: input is judged as given (so `U+0958` + nukta is flagged as a double
  nukta even though NFC would produce the same bytes as `क़`).
- The corruption generator and the score-versus-noise chart exist only as a design document.
- The case table encodes the author's reading of the Unicode Standard chapter 12 rules and common
  OCR and legacy-font failure modes; a native-speaker review is wanted before 0.1.

## Roadmap

| Sprint | Dates | Deliverable | Done when |
| --- | --- | --- | --- |
| 1 | 9 to 22 Nov 2026 | Skeleton, licence, CI, tests-first case table, rules doc, corruption-generator design (this release) | `cargo test` green on three OSes; `cargo test -- --ignored` fails on the harness |
| 2 | 23 Nov to 6 Dec 2026 | Devanagari validator passing every case in `tests/cases/devanagari.toml`; [corruption generator](docs/corruption-generator.md) implemented (`glyphsift corrupt`); score-versus-noise chart; three-runtime determinism check; 10k-cluster benchmark | Score falls monotonically as noise rises at every `p` in `{0, 0.01, 0.02, 0.05, 0.1, 0.2, 0.4}` for every noise family; native, Python and WASM reports byte-identical |
| 3 | 7 to 20 Dec 2026 | v0.1: WASM demo with per-line heatmap, Python wheel, CLI | `pip install` and `npm install` both work from a clean machine |
| later | | Tamil or Bengali; language-independent scoring | |

## Security and privacy

- No network egress: the core, the CLI, the wheel and the WASM build make no network requests and
  send no telemetry.
- What is stored where: nothing. The CLI reads the file (or stdin) it is given and writes to
  stdout; the library holds the input only for the duration of the call.
- Inputs are treated as untrusted text: the validator never interprets them, allocates in
  proportion to their length and has no recursion over input.
- Report vulnerabilities as described in [SECURITY.md](SECURITY.md).

## Develop

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test                                     # core + cli; the Sprint 2 harness is #[ignore]d
cargo test -p glyphsift-core -- --ignored      # runs the harness; fails until the validator exists
cargo check -p glyphsift-core --target wasm32-unknown-unknown
cargo check -p glyphsift-wasm --target wasm32-unknown-unknown
cargo check -p glyphsift-py                    # needs a python3 on PATH for the PyO3 build script
cargo tree --workspace -e normal -f '{p} {l}' | grep -Ei 'GPL|AGPL|LGPL|SSPL'   # must print nothing
cargo tree --workspace -f '{p} {f}' | grep preserve_order                       # must print nothing
scripts/build-demo.sh                          # the Pages demo; CI's `demo` job runs the same command
```

Tests come before implementation: add a case to `tests/cases/devanagari.toml` first, then make it
pass. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). The licence was chosen on day one and
will not change.
