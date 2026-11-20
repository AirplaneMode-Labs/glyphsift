# glyphsift 0.1.3: what it measures, what held up and what did not

Status: **draft, not published.** Written 20 Nov 2026 for release row 7 of [release.md](release.md). It uses only evidence that exists today: every figure names the committed file
it comes from, and a figure without a path is not in this draft. The 8 GB laptop figures read "not measured on 8 GB" because nobody has measured them, so the draft cannot be
finished until [row 2](release.md) closes. Nothing is published, tagged or announced, and nothing is claimed beyond what the files show. The only text about results that may be quoted
outside this repository is [what-glyphsift-measures.md](what-glyphsift-measures.md); this draft adds nothing to it except the release path.

## What it is

A deterministic, non-ML check of whether extracted Devanagari text is structurally clean: it splits the text into UAX #29 grapheme clusters and applies 16 structural rules
(`docs/devanagari-rules.md`), gives a document score and per-line scores in parts per million, and a per-chunk gate (`pass`, `hold`, `not_scored`). One Rust core builds to a command-line
tool, a Python wheel and a WebAssembly package; there is no model and no network. It measures broken structure, not whether the words are right (see "What did not hold up").

## What was tried

- **A rule table written before the validator**: 154 hand-written synthetic cases, each with its expected clusters and issues (`crates/glyphsift-core/tests/cases/devanagari.toml`).
- **A seeded corruption generator** that damages clean synthetic text in 19 named ways plus a `mixed` mode (`docs/corruption-generator.md`), and a benchmark that scores the damaged text
  (`docs/score-vs-noise.csv`: 420 rows, 20 noise families, 7 noise levels, 3 seeds).
- **A gate** with a default threshold of 975000 ppm, derived from that benchmark (`docs/gate.md`, `crates/glyphsift-core/src/gate.rs`).
- **The same bytes on every runtime**: native, Python and WASM compared on committed bytes (`tests/determinism`, `scripts/determinism.sh`).
- **Sprint 7, the release path, in code**: the artefacts built as a release builds them, each installed into a fresh place and called, and a rehearsal of the signed release with a public test key
  (`scripts/release/rehearse.sh`, [RELEASING.md](RELEASING.md)).

## What held up

| What | Result | Where |
|---|---|---|
| The score falls as injected noise rises | 0 of 60 (family, seed) series rise; the score is 1,000,000 at p=0 in every row | `docs/score-vs-noise.csv`, `docs/what-glyphsift-measures.md` |
| The gate threshold sits between two noise levels | 975000 ppm lies in a 12,327 ppm gap between the worst `mixed` seed at p=0.1 and the best at p=0.2 | `docs/what-glyphsift-measures.md`, `docs/score-vs-noise.csv` |
| The same bytes on native, Python and WASM | 13 sample texts and 200 gate cases byte-identical (77 pass, 92 hold, 24 not_scored, 7 rejected) | `tests/determinism/expected`, `tests/determinism/gate/expected.jsonl` |
| An installed artefact gives the committed bytes | on macOS arm64, from a copy with no sibling repository: the npm tarball in an empty project, the wheel in a fresh `.venv`, and the CLI built from the unpacked packaged crates with nothing from a registry each gave the committed report and gate bytes for one clean and one corrupted sample, and two rehearsal runs gave byte-identical `SHA256SUMS` and manifest | `evidence/sprint-7/D3/green/rehearse-macos-run1.log`, `rehearse-macos-run2.log` |
| A test-key signature is refused without the explicit flag | `refused: test_key_refused`, and `refused: no_trusted_key` against the committed, empty `docs/release-keys.json` | the same logs |
| The quick start still works | the README's two-minute section was run from the built files in a fresh directory; eleven single-line breaks of it each turned the test red | `evidence/sprint-7/D3/green/D3-04-quickstart-breaks.log` |

## What did not hold up, or is not claimed

- **Seven noise families never move the score** (`digit_danda`, `matra_drop`, `matra_swap`, `nukta_loss`, `ocr_confusion`, `reph_misplace`, `virama_delete`: every row is 1,000,000 in `docs/score-vs-noise.csv`): they change the
  text without breaking a structural rule. A pass means no structural damage above the threshold was found, not that the text is correct.
- **Part of the fall is by construction**: damaged sites at one noise level are a subset of those at the next, so the curve shows that the score responds to injected structural damage, not that it predicts the
  quality of any real document.
- **Synthetic text only**: the corpus, the noise and every sample are invented; no real document has been scored; the weights are an author's judgement and were not tuned on the benchmark; the gate threshold was
  derived from synthetic noise and a user with a sample set should expect to move it.
- **Devanagari only**: a second script (Tamil, planned for v0.2) is a design note, not code (`docs/v0.2-tamil.md`).
- **Not run yet**: the Linux and Windows runs of the release rehearsal and the Windows junction case of the shared vectors can only be shown by CI after the push; the wheels and packages of 0.1.3 exist only as local and CI
  files, not on any registry.

## On the 8 GB Windows laptop without a GPU

| What | Result |
|---|---|
| Time to score a 1 MiB text, native | not measured on 8 GB |
| Time to score a 1 MiB text, WebAssembly in Node | not measured on 8 GB |
| Time to score a 1 MiB text in the browser demo | not measured on 8 GB |
| Peak memory | not measured on 8 GB |

The procedure is in [release.md](release.md), "Owner must", row 2. The README's Benchmarks tables carry Apple-silicon figures with that column filled in as "not measured on 8 GB". The raw files behind every figure, each with its date, commit, machine and command, are in [benchmarks/](benchmarks/README.md).

## Install, today

Not published yet: the npm scope `@airplanemode` and the PyPI and crates.io names are not reserved, no signing key exists and no tag exists. The commands that work today build from a clone: the README's
[Try it in two minutes](../README.md#try-it-in-two-minutes). After the owner's steps ([RELEASING.md](RELEASING.md)) the registry commands in the README's Install section will apply; they have not been run.
