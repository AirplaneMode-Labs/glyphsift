# glyphsift

Scores whether extracted Indic text is clean enough to trust or train on: a deterministic
Devanagari grapheme-cluster validator with a Rust core, a WASM build for the browser, a Python
wheel and a CLI. Sixteen structural rules, a document score from 0 to 1, per-line scores, no model
and no network.

Part of [Airplane Mode Labs](https://github.com/AirplaneMode-Labs), an open-core, offline-first,
browser-native AI infrastructure lab. Package names use the placeholder scope `@airplanemode` /
crate and package names `glyphsift` until the handles are reserved; nothing is published yet.

## Status

Sprint 4: glyphsift **0.1.0 is a release candidate, not tagged**. The validator, the score, the CLI, the
WASM and Python bindings, the score-versus-noise benchmark and the demo (with a per-cluster heatmap and
local-file input) work and are tested on this repository's synthetic text only. The scoring did not change in
Sprint 4: the benchmark CSV and the reports are byte-identical, and the WASM module is the Sprint 3 module. A Python
wheel and an npm tarball were built and installed from local files on macOS arm64; nothing is published, tagged or
signed. Sprint 4 added hashed tool installs and a `wheels` CI job (Linux, Windows and macOS wheels plus an sdist),
a fix for `scripts/package-npm.sh` on macOS (BUG-T2-S3-19-R2), and a demo footer that opens the third-party
notices as `NOTICE.txt` instead of downloading them. Not yet: scripts other than Devanagari (Tamil planned for v0.2,
design note [docs/v0.2-tamil.md](docs/v0.2-tamil.md), nothing implemented), a published package or wheel; Linux and
Windows wheels are built only by CI after the owner's push. What is open before a tag is in
[docs/release.md](docs/release.md): CI read on three operating systems after the push, the 8 GB laptop benchmark
(not measured on 8 GB), signed artifacts, the tag, publishing and the write-up.

## Install

Not published yet: the npm scope @airplanemode and the PyPI and crates.io names are not reserved. The commands below were proven from locally built artifacts on macOS arm64 (an npm pack tarball installed offline into a fresh empty directory, a wheel installed into a fresh venv); publishing to the registries is the owner's step.

From a clone of this repository (Rust 1.98 comes from `rust-toolchain.toml`):

```sh
# Command line: installs the `glyphsift` binary (0.1.0) under <dir>/bin. The RUSTFLAGS prefix keeps your home
# and checkout paths out of the binary (optional; scripts/remap-paths.sh sets the same flags for the build scripts)
RUSTFLAGS="--remap-path-prefix=$HOME/.cargo=/cargo --remap-path-prefix=$HOME/.rustup=/rustup --remap-path-prefix=$PWD=/glyphsift" cargo install --path crates/glyphsift-cli --locked --root <dir>

# Python wheel (abi3, CPython >= 3.9): built, then installed into a fresh venv, offline
# (scripts/package-python.sh does this with the tool versions pinned and the builder paths remapped; CI gives it
# uv, maturin and mypy from tools/ci/requirements.txt, pinned by hash: python -m pip install --require-hashes
# --no-deps --only-binary=:all: -r tools/ci/requirements.txt, then GLYPHSIFT_TOOLS_VENV=<that venv>)
. scripts/remap-paths.sh && uvx maturin@1.16.0 build --release --locked -m crates/glyphsift-py/Cargo.toml -o target/wheels
python3 -m venv venv && venv/bin/pip install --no-index --no-deps target/wheels/glyphsift-0.1.0-cp39-abi3-macosx_11_0_arm64.whl
uv venv uvenv && uv pip install --offline --no-index --no-deps --python uvenv/bin/python target/wheels/glyphsift-0.1.0-cp39-abi3-macosx_11_0_arm64.whl

# npm package @airplanemode/glyphsift (WASM, Node and browser): packed, then installed offline into an empty directory
scripts/install-wasm-tools.sh    # wasm-bindgen 0.2.129 and binaryen from digest-pinned release binaries (default ~/.local/glyphsift-tools)
scripts/build-wasm.sh && scripts/package-npm.sh      # dist/npm/airplanemode-glyphsift-0.1.0.tgz
mkdir app && cd app && npm init -y && npm i ../dist/npm/airplanemode-glyphsift-0.1.0.tgz --ignore-scripts --offline --no-audit --no-fund

# The demo: demo/dist/ (runs build-wasm.sh first)
scripts/build-demo.sh
```

What was proven, and where: the wheel is `glyphsift-0.1.0-cp39-abi3-macosx_11_0_arm64.whl`, platform tag
`macosx_11_0_arm64`, and it installed with `python3 -m venv` plus `pip install --no-index --no-deps` and with
`uv venv` plus `uv pip install --offline --no-index --no-deps`, each followed by a `python -I` call that printed
750000 for `score_ppm('कखग\ufffd')` (`evidence/sprint-3/D3/install-wheel-r2.log`). **Linux and Windows wheels are not built yet**
(they and a source distribution are built only by CI after the owner's push, in the `wheels` job; nothing from it is published, and `docs/release.md` lists what only CI can prove). The npm tarball installed offline from an empty
cache with install scripts off; `npm ls` showed exactly that one package, and a Node call and a bundler-free
page in installed Chrome gave the report `glyphsift check` prints (`evidence/sprint-3/D3/npm-install-r2.log`). The CLI
installed with `cargo install --path` and ran with every documented exit code
(`evidence/sprint-3/D3/cli-install-r2.log`). The wheel, the tarball and each crate carry `LICENSE` and `NOTICE`. The wheel and the tarball contain no test data,
no source map, no install script and no file over 5 MB. The source packages `cargo package --list` would upload
do include each crate's `tests/` (`glyphsift-core` ships `tests/cases/devanagari.toml`, invented strings, and `tests/*.rs`;
`glyphsift-cli` ships `tests/*.rs`) so the crates can be tested from the registry; that is intended. Third-party crates
and the compiled Unicode tables that ship inside the wheel, the WASM and the CLI are listed with their licences in
[NOTICE](NOTICE). Builder paths (home, cargo, rustup and checkout directories) are remapped out of the Rust builds with
`--remap-path-prefix` (`scripts/remap-paths.sh`) and `scripts/package-python.sh` and `scripts/package-npm.sh` fail if
any packed file contains `/Users/`, `/home/` or the scratch-directory prefix (`scripts/check-no-builder-paths.py`).

### After the owner publishes

Once the handles are reserved and the artifacts are published, these will work; they have not been run:

```sh
pip install glyphsift
npm i @airplanemode/glyphsift
cargo install glyphsift-cli
```

## Quick start

### CLI

```sh
echo 'नमस्ते।' | glyphsift check -
# {"spec":"glyphsift.report/0.2","script":"devanagari","code_points":7,"clusters":[...],"issues":[],
#  "summary":{...},"lines":[{"index":0,...,"score_ppm":1000000}],"score":{"ppm":1000000,"penalty":0,...}}

printf 'कखग\xef\xbf\xbd' | glyphsift check - --fail-under 800000 > /dev/null; echo $?
# score 750000 is below 800000: the report is printed, the exit code is 4
```

(From a clone, `cargo run -q -p glyphsift-cli -- check -` runs the same thing without installing.)

- `glyphsift check FILE|- [--fail-under PPM]` validates UTF-8 text from a file or standard input (up to 4 MiB)
  and prints the canonical JSON report. `--fail-under` is a threshold in parts per million, 0 to 1000000.
- `glyphsift corrupt --family <name>|mixed --p <decimal> --seed <u64> [--sites <path>]` applies a seeded
  OCR-noise family to clean text on standard input (`--list-families` prints the 19 names and `mixed`).
- `glyphsift bench --corpus <path> --seeds 1,2,3 --csv <path> --svg <path>` runs the score-versus-noise
  benchmark and writes the CSV and the chart; `glyphsift bench --verify <csv>` re-checks an existing CSV.
- `glyphsift --help`, `glyphsift <command> --help` and `glyphsift --version` (0.1.0) exit 0.

Exit codes, the same for every command:

| Code | Meaning |
|---|---|
| 0 | Success: `check` printed the report and the score is not under `--fail-under`; `corrupt` wrote its output; `bench` met the criterion (or `--verify` passed) |
| 1 | I/O error, invalid UTF-8, input over 4 MiB, or a failed `bench` criterion (`bench --verify` on a CSV that violates it) |
| 2 | Usage error: missing or bad arguments, an unknown command or family |
| 4 | `check --fail-under`: the score is below the threshold (the report is still printed) |

There is no exit code 3. Installing the CLI from the crates.io registry works only after the owner publishes
(see "After the owner publishes" above); until then the proven command is
`cargo install --path crates/glyphsift-cli --locked --root <dir>` (prefix it with the `RUSTFLAGS=...` shown under Install to
keep builder paths out of the binary).

The corruption generator and the benchmark:

```sh
glyphsift corrupt --family matra_detach --p 0.05 --seed 7 < bench/corpus/clean.txt > out.txt
glyphsift corrupt --list-families
glyphsift bench --corpus bench/corpus/clean.txt --seeds 1,2,3 --csv docs/score-vs-noise.csv --svg docs/score-vs-noise.svg
```

### Python

```python
import json, glyphsift

report = json.loads(glyphsift.validate("नमस्ते।"))   # the same bytes as `glyphsift check`
print(report["score"]["ppm"])                         # 1000000 is clean
print(glyphsift.score_ppm("कखग\ufffd"))               # 750000
print(glyphsift.clusters("नमस्ते।"))                  # ['न', 'म', 'स्ते', '।']
```

`validate`, `score_ppm` and `clusters` raise `ValueError` over 4 MiB. The wheel ships type stubs (`glyphsift.pyi`,
`py.typed`); `mypy --strict` passes on a script that uses them.

### Node and the browser

```js
const { validate, score_ppm } = require("@airplanemode/glyphsift");   // Node: no init() needed
console.log(JSON.parse(validate("नमस्ते।")).score.ppm);               // 1000000
```

```html
<script type="module">   <!-- browser, no bundler -->
  import init, { validate } from "./node_modules/@airplanemode/glyphsift/web/glyphsift.js";
  await init();
  console.log(JSON.parse(validate("नमस्ते।")).score.ppm);
</script>
```

Exports: `validate(text)`, `score_ppm(text)`, `report_spec()`, `clusters(text)`, `clusters_json(text)`,
`issue_kinds()`; nothing else. For valid Unicode text, all three runtimes return byte-identical reports.

## How it works

1. Text is split into UAX #29 extended grapheme clusters (unicode-segmentation 1.13, including the
   Unicode 15.1 GB9c conjunct rule, so `क्ष` is one cluster).
2. Each cluster is parsed once, left to right, against the Devanagari cluster grammar
   `(C nukta? virama (ZWJ|ZWNJ)?)* C nukta? matra? (anusvara|chandrabindu)? visarga?` and its
   alternatives for independent vowels and standalone signs, and checked by sixteen rules, each
   a small predicate with a stable name (`dependent_vowel_without_base`, `double_matra`,
   `virama_after_matra`, `zwj_zwnj_misplaced`, `mixed_script_in_cluster`, `control_character`, ...).
   Two rules look at the cluster's first code point: a joiner (ZWJ, ZWNJ) is flagged only in a
   Devanagari-based cluster or when it starts a cluster, so emoji sequences and Persian words are left
   alone, and invisible tag characters and non-Indic combining marks on a Devanagari letter are flagged.
   The code-point tables, the grammar and every rule are in
   [docs/devanagari-rules.md](docs/devanagari-rules.md); the executable form is the case table
   `crates/glyphsift-core/tests/cases/devanagari.toml` (154 cases, written before the code).
3. Each flagged cluster costs the **largest** weight among its issues. Weights are integers from 1
   to 1000, one per rule, in [crates/glyphsift-core/weights/devanagari.toml](crates/glyphsift-core/weights/devanagari.toml),
   every line with a `# source:` comment. The document score is an integer in parts per million:

   ```text
   ppm = 1_000_000 - floor(penalty * 1000 / cluster_count)      (saturating; 1_000_000 for empty input)
   ```

   so one broken cluster out of four at weight 1000 scores 750_000. The same formula gives a score per
   line (`lines[i].score_ppm`; LF, CRLF or a bare CR ends a line). Shown with four decimals by integer
   formatting, truncated: 704762 is 0.7047.
4. The report (`glyphsift.report/0.2`) is serialised as compact JSON with fields in declaration order
   and no floating point, so for valid Unicode text native, Python and WASM builds emit byte-identical output.

Determinism is enforced: `clippy.toml` forbids hash-based collections and the platform `libm`, a test
scans `glyphsift-core/src` for floating-point types and hash collections, and the core reads no
clock, environment or file.

## Contracts

glyphsift consumes no runtime/spec contract yet and emits no events: the text being scored never leaves the
process. Emitting `airplanemode.event/0.1` timings is not implemented. Its own wire format is the report,
`glyphsift.report/0.2` (docs/devanagari-rules.md section 5), which Sprint 3 left unchanged: no rule was added or
removed and no weight changed, so reports from 0.2 consumers keep their shape.

## Demo

Live demo: <https://airplanemode-labs.github.io/glyphsift/>. Built from `main` by
`.github/workflows/pages.yml` on every push, with a box titled "What this demo does not do yet". It
runs entirely in the browser: no upload, no analytics, no third-party scripts or fonts. (The Sprint 3 and Sprint 4
changes are committed locally and not pushed: the live page shows Sprint 2 until the owner pushes and the workflow
runs. The Sprint 4 demo was proven on a local build served under `/glyphsift/`.) The footer links the third-party
notices as `NOTICE.txt`, which Pages serves as `text/plain` so that it opens in the browser instead of downloading
(BUG-T1-S3-R2-01); it carries the MIT texts of the WebAssembly crates that are not offered under Apache-2.0, among
them zmij (its licence file has no copyright line, so the notice names the author from its `Cargo.toml`)
(`evidence/sprint-4/D3/green-D3-03.log`).

It shows the real report for pasted text, a local `.txt` file or one of five synthetic samples (clean,
OCR-corrupted, legacy font read as Latin, legacy font residue, adversarial):

- the document score with four decimals;
- **a heatmap**: one row per line with a strip shaded by the sum of the weights of that line's issues, then every
  grapheme cluster of the line shaded by the sum of the weights of the rules that fired on it (buckets: clean 0,
  low 1 to 399, mid 400 to 799, high 800 and above; underline style and weight repeat the bucket so colour is not
  the only cue; hover a cluster for its rules; capped at 20,000 clusters with a note);
- the sixteen rules with their weights and how often each fired, a per-line table, the clusters, and the canonical
  JSON, which is byte for byte what `glyphsift check -` prints for the same text.

**Local files**: drop a `.txt` file on the drop zone or choose one with the file picker. The file is read in the
tab with `File.arrayBuffer()` after its size is checked (over 1 MiB is refused unread, with "This file is over 1 MiB"),
decoded with a fatal UTF-8 decoder (invalid bytes are refused with "This file is not valid UTF-8 text"), and the
decoded text is validated exactly, so the report equals `glyphsift check FILE`, BOM and CRLF included. Nothing is
uploaded and no request is made. Pasted input over 1 MiB is refused before the WASM module is called. Every
report-derived, file-derived and pasted string is rendered with `textContent`, every attribute is set with
`setAttribute` from a fixed set of values, and no element carries a style attribute. Sources in `demo/`;
`scripts/build-demo.sh` assembles `demo/dist/` (git-ignored). Verification: see Develop; the run that checked
all of this is `evidence/sprint-3/D3/green-D3-07.log`, with screenshots `evidence/sprint-3/D3/shots/`.

## Benchmarks

![Document score versus synthetic OCR noise: the mixed family's mean score and min-to-max band, twelve triggering families as thin lines, seven none-directly families as dashed lines](docs/score-vs-noise.svg)

Reproduce (about one second in release mode; the CSV and SVG come out byte-identical every time):

```sh
cargo run -p glyphsift-cli --release -- bench --corpus bench/corpus/clean.txt --seeds 1,2,3 --csv docs/score-vs-noise.csv --svg docs/score-vs-noise.svg
```

The benchmark corrupts the 288-line synthetic Hindi and Marathi corpus `bench/corpus/clean.txt`
(6,117 clusters, every line validating with zero issues) at p in {0, 0.01, 0.02, 0.05, 0.1, 0.2, 0.4}
with each of the 19 noise families of [docs/corruption-generator.md](docs/corruption-generator.md)
and with `mixed` (every family on a disjoint partition of the sites), seeds 1 to 3, and scores each
result. The command exits 1 on any violation of this criterion:

- (a) the mixed-family mean score (over seeds) falls STRICTLY at every consecutive step from p=0 to p=0.4;
- (b) mixed is non-increasing in p for each seed;
- (c) every triggering family is non-increasing in p for each seed;
- (d) score_ppm is 1_000_000 at p=0 for every row.

"Triggering" means the family's "rules it should trigger" column in the corruption doc names rules
(twelve families); the other seven are "none directly" and are reported, not gated. All four parts
hold on the committed `docs/score-vs-noise.csv` (420 rows), and `glyphsift bench --verify
docs/score-vs-noise.csv` re-checks them without regenerating.

**Regenerated in Sprint 3.** Restricting the joiner rule to Devanagari bases (BUG-T2-S2-07) changed 35 rows of the
CSV: the 18 `joiner_inject` rows and the 17 `mixed` rows with p above 0. A joiner injected after a space or other
non-Devanagari cluster is no longer flagged, so those sites cost nothing, and the benchmark's `joiner_inject` sites
declare no expected rule there (recall is still 1.000000). No other row changed, and the weights file and the
corpus did not (their SHA-256 are in the log). The committed CSV was `d20efc20...`; the regenerated one is
`cac89041...` and the SVG changed with it. Two fresh runs are byte-identical, the criterion holds, and the tables
below were regenerated from the new CSV. Evidence: `evidence/sprint-3/D3/bench-s3.log` (hashes before the run, two runs
with SHA-256 of the CSV and SVG, the comparison with the committed files, `--verify`). The Sprint 2 run, on the old
rules, is `evidence/sprint-2/D3/bench-determinism.log`. Numbers below are from `docs/score-vs-noise.csv` and are
scores, 1.0000 being clean; figures are rounded half-up to four decimals (score_ppm divided by 1,000,000).

| Mixed family | p=0 | p=0.01 | p=0.02 | p=0.05 | p=0.1 | p=0.2 | p=0.4 | 8 GB Windows no-GPU laptop |
|---|---|---|---|---|---|---|---|---|
| mean of seeds 1 to 3 | 1.0000 | 0.9985 | 0.9970 | 0.9917 | 0.9840 | 0.9675 | 0.9334 | not measured |
| minimum | 1.0000 | 0.9983 | 0.9969 | 0.9911 | 0.9828 | 0.9651 | 0.9321 | not measured |
| maximum | 1.0000 | 0.9988 | 0.9971 | 0.9927 | 0.9852 | 0.9705 | 0.9359 | not measured |

The twelve triggering families, mean of seeds 1 to 3:

| Family | p=0.05 | p=0.4 | 8 GB Windows no-GPU laptop |
|---|---|---|---|
| `matra_double` | 0.9865 | 0.8906 | not measured |
| `matra_detach` | 0.9846 | 0.8788 | not measured |
| `nukta_spurious` | 0.9959 | 0.9669 | not measured |
| `virama_insert` | 0.9748 | 0.8143 | not measured |
| `bindu_swap` | 0.9999 | 0.9991 | not measured |
| `sign_order` | 0.9995 | 0.9956 | not measured |
| `joiner_inject` | 0.9935 | 0.9420 | not measured |
| `legacy_font` | 0.9989 | 0.9894 | not measured |
| `word_boundary` | 0.9838 | 0.8643 | not measured |
| `random_substitution` | 0.9927 | 0.9427 | not measured |
| `mixed_script` | 0.9806 | 0.8510 | not measured |
| `control_leak` | 0.9516 | 0.7108 | not measured |

Scores are deterministic (byte-identical across native, Python and WASM in scripts/determinism.sh) for valid Unicode text. Not measured on 8 GB: no run on the 8 GB Windows laptop has been made, and every figure here comes from the Apple M5 Pro, 48 GB development Mac.

Recall at p=0.05, the share of corrupted sites that declare an expected rule for which that rule fired in
the damaged cluster, is 1.000000 for every family that declares a rule, in every seed that has one
(`bindu_swap` declares a rule only on its 20% keep-both branch, so seed 3 has none at p=0.05; the
`recall_ppm` column of the CSV is empty where no site declares a rule).

| Throughput on about 1 MiB of the synthetic corpus (1,048,569 bytes, 12,888 lines, 273,779 clusters) | Apple M5 Pro, 48 GB (macOS 27.2.1) | 8 GB Windows no-GPU laptop |
|---|---|---|
| native `glyphsift check`, wall clock, best of 5 | 61 ms (one cold run 396 ms) | not measured |
| WASM `validate()` in Node 22, best of 5 | 220 ms | not measured |
| WASM `score_ppm()` in Node 22, best of 5 | 74 ms | not measured |
| demo in Chrome: 1 MiB pasted, validated and rendered | 1,462 ms (headless Chrome, includes the 20,000-cluster heatmap) | not measured |
| peak memory | not measured | not measured |

Command and evidence: `evidence/sprint-3/D3/throughput.log` (the native line is the release `glyphsift check` on the 1 MiB
file, five runs including process start; the WASM lines are `validate()` and `score_ppm()` from `dist/wasm/nodejs` on the
same text, best of five; the demo line is from `evidence/sprint-3/D3/green-D3-07.log`). The Apple-silicon column is the
development Mac (Apple M5 Pro, 48 GB), not the target. The 8 GB Windows no-GPU laptop column is the owner's step (docs/release.md, row 2); it stays "not measured" until that run exists.
Browser figures other than the demo line, lines per second in the browser, and memory peak: not measured.

## Limitations

- **Structural checks only.** The validator judges the order and combination of code points inside
  one cluster. It has no dictionary and no language model: a well-formed nonsense word scores clean, and
  so does a visually plausible OCR confusion (`ब` for `व`).
- **The "none directly" families are invisible to it, by design.** Seven noise families change the
  text without breaking any structural rule, and the score does not move for them. Their curves
  (`docs/score-vs-noise.csv`, mean of seeds 1 to 3, every step 1.0000):

  | Family | p=0 | p=0.01 | p=0.02 | p=0.05 | p=0.1 | p=0.2 | p=0.4 |
  |---|---|---|---|---|---|---|---|
  | `matra_drop` | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 |
  | `matra_swap` | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 |
  | `nukta_loss` | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 |
  | `virama_delete` | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 |
  | `reph_misplace` | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 |
  | `ocr_confusion` | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 |
  | `digit_danda` | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 |

  Legacy-font text read back as Latin letters is the same kind of blind spot: it scores 1.0000.
- **The benchmark proves a narrow thing.** The score falls as injected structural damage rises, on 288
  invented lines. The noise is synthetic, each family's expected rules were chosen by the author, the
  weights were set by the author before the first run and were never tuned on the benchmark, and the
  monotone fall is partly by construction (the corrupted sites at one p are a subset of those at the
  next, and a flagged cluster only adds penalty). It is not a measurement of real OCR or of how well the
  score predicts the quality of a real document. No real document has been scored.
- **Devanagari only.** Text in other scripts is plain text and is never flagged. Tamil planned for v0.2, Bengali later;
  [docs/v0.2-tamil.md](docs/v0.2-tamil.md) is a design note with no code, and nothing for Tamil is implemented.
- **Joiners and tags are judged by the cluster's first code point.** A ZWJ or ZWNJ is flagged only in a
  Devanagari-based cluster or when it starts a cluster, so a joiner that joins a space's cluster (`" "` plus
  ZWJ) or punctuation is not flagged, and neither is invisible text in a non-Devanagari cluster (a tag
  character after a Latin letter). This was chosen over the old behaviour (every misplaced joiner flagged,
  which penalised emoji and Persian text); it lowers sensitivity to a joiner injected after a space: on the
  benchmark, 599 of 807 injected joiners at p=0.05 land in Devanagari clusters and are flagged, the rest cost nothing.
- **Variation selectors are not flagged.** `U+FE00..U+FE0F` and `U+E0100..U+E01EF` are combining marks, but a
  Devanagari consonant followed by one scores clean. Vedic Extensions marks (`U+1CD0..U+1CFF`) on a Devanagari
  base are not flagged either, and a combining grapheme joiner (`U+034F`) is flagged as a foreign mark.
- **Invisible text is not fully caught.** These score clean today, each pinned by a `known_gap_*` table case:
  `U+200B` ZWSP, `U+2060` word joiner, `U+00AD` soft hyphen, `U+2062` invisible times, and in-cluster Extend
  characters that are not Mn, Mc or Me (`U+1F3FB..U+1F3FF`, `U+FF9E`, `U+FF9F`). The invisible-text gap is not fully
  closed (docs/devanagari-rules.md section 7).
- **Lone surrogates, and "identical results" means valid Unicode text.** Python raises `UnicodeEncodeError` on a
  lone surrogate, WASM and JavaScript substitute `U+FFFD` and report `unexpected_code_point`, and the CLI refuses
  invalid UTF-8 (exit 1). Native, Python and WASM are byte-identical for valid Unicode text only.
- **Clusters are judged in isolation.** Word- and document-level signals (legacy-font detection, a run of
  meaningless words, repeated clusters) are not implemented.
- **No normalisation.** Input is judged as given, so `U+0958` plus a nukta is a double nukta even
  though NFC would give the same bytes as `क़`. Devanagari Extended cantillation marks are flagged as
  unexpected (docs/devanagari-rules.md section 7).
- **Input limit.** `validate` (CLI, Python and WASM) and `clusters` (Python and WASM) refuse input
  over 4 MiB with the same "too large" error (the report holds one record per cluster); the demo
  accepts at most 1 MiB. Over a 1 MiB input the report is large (the WASM safety script runs one).
- **Demo.** No service worker, so offline after the first load is best effort. Local files must be UTF-8 text of
  at most 1 MiB; PDFs, other encodings and larger files are refused. See its "What this demo does not do yet" box.
- **Third-party notices are a list, not a bundle.** `NOTICE` names every crate compiled into the artifacts with its
  licence, including the compiled Unicode tables (`unicode-general-category`, Apache-2.0), and names the author of the
  MIT-only crate zmij (its licence file has no copyright line). The full licence texts of those crates are not copied
  into the wheel or the tarball; the MIT texts of zmij and memchr are in the demo's `NOTICE.txt` and in each crate's
  source package. The wheel carries no SBOM (maturin's Rust SBOM embeds the
  builder's checkout path, so it is switched off in `crates/glyphsift-py/pyproject.toml`). Generating a
  `THIRD-PARTY-NOTICES` file with the full texts (cargo-about) is a pre-publish step for the owner. The wheel is tagged
  `Operating System :: MacOS` until Linux and Windows wheels exist.
- **Release candidate, nothing published, one platform proven.** No tag, no crate, wheel or npm package is on a registry,
  and the names and the npm scope are not reserved. Only a macOS arm64 wheel (`macosx_11_0_arm64`) was built and
  installed. Linux and Windows wheels are built only by CI after the owner's push (the `wheels` job: manylinux_2_17
  through zig on Ubuntu, `win_amd64` on Windows, plus an sdist): configured, never run, and the package's OS
  classifiers stay "MacOS" until those wheels are proven. The npm
  tarball was installed in Node 22 and in Chrome only (not Firefox or Safari). Nothing is signed: the release
  manifest tool and a dry run with the public test key exist, the real key does not.
- **Windows and CI.** The three-OS CI (`check`, `determinism`, `deny`, `demo`) last ran green on 9 Nov 2026 on the Sprint 2
  commit ([run](https://github.com/AirplaneMode-Labs/glyphsift/actions/runs/42635283936), 9 of 9 jobs). The Sprint 3 and
  Sprint 4 changes, the `packaging` and `demo-browser` jobs (now with hashed tool installs and a Playwright lockfile)
  and the new `wheels` job have run on macOS arm64 only. Three-OS status: tests-first evidence Done (red/green logs);
  local macOS green; CI on three OSes configured, pending the owner's push. Hashed installs cover uv, maturin, mypy and ziglang (`tools/ci/requirements.txt`) and Playwright
  (`tools/playwright/package-lock.json`, `npm ci --ignore-scripts`); known gaps: the pip that `setup-python` ships is
  not pinned, and `scripts/determinism.sh` installs maturin by version only into a test-only venv. Even then a hosted
  Windows runner is not the target laptop: the 8 GB Windows no-GPU column above reads "not measured", and the prose
  says it again: not measured on 8 GB.
- **Native-speaker review wanted.** The case table encodes the author's reading of the Unicode Standard
  chapter 12 and common OCR and legacy-font failure modes; the corpus is invented by the author.
- **What comes next.** The owner's steps in [docs/release.md](docs/release.md) (push and read CI, the 8 GB benchmark,
  signing, tag, publish); reading the first CI run of the `wheels` job; Tamil for v0.2, then Bengali, and
  language-independent scoring.

## Security and privacy

- No network egress: the core, the CLI, the wheel, the npm package and the WASM build make no network requests and
  send no telemetry. The demo makes requests only for its own files, under a CSP with no inline script
  or style and `connect-src 'self'`; reading a local file makes no request (checked: 0 requests during every
  file action).
- What is stored where: nothing. The CLI reads the file (or stdin) it is given and writes to
  stdout; the library holds the input only for the duration of the call.
- Inputs are treated as untrusted text: the validator never interprets them, allocates in
  proportion to their length, caps input at 4 MiB, and has no recursion over input. A 20,000-string
  fuzz test (native) and the same set in WASM (`tests/wasm/run_wasm_safety.mjs`) finish with no panic and
  no trap, and a 5,000-mark run takes about twice as long as a 2,500-mark run (linear).
- The packed artifacts (wheel, npm tarball) hold only the compiled module, its type declarations, the README and the
  licence files: no install or lifecycle script, no dependency, no source map, no test data, no file over 5 MB.
  The wheel and the tarball were installed with scripts off, offline, from an empty cache.
- The benchmark's SVG is inert: no script, event handler, link or external reference, all text escaped
  (tests assert it). The demo renders every report-derived and pasted string with `textContent` only;
  `scripts/check-demo-sources.sh` fails the build on `innerHTML`, `outerHTML` or `insertAdjacentHTML`.
- Supply chain: CI downloads cargo-deny, wasm-bindgen and binaryen as release binaries and checks each
  against a SHA-256 pinned in the repository before use; every action is pinned by commit SHA.
- Report vulnerabilities as described in [SECURITY.md](SECURITY.md).

## Develop

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --locked                            # core + cli: 154-case table, fuzz, score, corruption, check, bench, CLI surface
cargo test --locked -p glyphsift-wasm          # the WASM bindings' native unit tests
cargo check --locked -p glyphsift-core --target wasm32-unknown-unknown
cargo check --locked -p glyphsift-wasm --target wasm32-unknown-unknown
cargo check --locked -p glyphsift-py           # needs a python3 on PATH for the PyO3 build script
cargo deny --all-features check                # needs cargo-deny 0.20.2; CI runs the pinned binary
scripts/determinism.sh                         # native, Python and WASM against tests/determinism/expected (13 samples), plus the WASM safety script
scripts/build-demo.sh                          # the Pages demo; CI's `demo` job runs the same command
cargo run --locked -q -p glyphsift-cli --release -- bench --verify docs/score-vs-noise.csv
tests/scripts/run-all.sh                       # script tests: release-manifest tool, lockfile and requirements hashes, CI policy, package-npm.sh with its default scratch folder
scripts/package-python.sh                      # builds the wheel, installs it into a venv from pip and from uv, runs mypy --strict on the stubs
scripts/package-npm.sh                         # packs the npm tarball and installs it offline into an empty directory (needs dist/wasm)
```

Browser checks of the built demo and of the installed npm package, in installed Chrome (Playwright 1.65.0 is
not a dependency of glyphsift; `tools/playwright` holds its lockfile, and `npm ci` pins every package by integrity hash):

```sh
npm ci --prefix tools/playwright --ignore-scripts
export PLAYWRIGHT_DIR=$PWD/tools/playwright
# the demo, under /glyphsift/ from a server that answers 404 for every other path
node tests/demo/check_demo.mjs --cli target/release/glyphsift [--shots <dir>]
# the npm package, bundler-free, from a fresh `npm i` directory (scripts/package-npm.sh runs this when PLAYWRIGHT_DIR is set)
node tests/npm/check_browser.mjs --dir <fresh install dir> --cli target/release/glyphsift
```

Tests come before implementation: add a case to `crates/glyphsift-core/tests/cases/devanagari.toml` first (the
file is the rules' specification), then make it pass; a weight or corpus change after the first benchmark run
is a `CHANGELOG.md` entry with its reason. The determinism samples contain invisible characters, CRLF and a
BOM on purpose; `.gitattributes` keeps git from normalising them. See [CONTRIBUTING.md](CONTRIBUTING.md) and
[docs/RELEASING.md](docs/RELEASING.md).

## Licence

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). The licence was chosen on day one and
will not change.
