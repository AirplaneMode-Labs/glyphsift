# The gate call

Status: implemented in Sprint 5 (TD-42), untagged, in glyphsift 0.1.1. The core function is `gate(text, threshold_ppm)`;
the CLI, the Python wheel and the WASM build (and so the npm package and the demo's Gate tab) expose it. Nothing here is
published. Every figure on this page comes from the Apple M5 Pro, 48 GB development Mac and from synthetic text: not measured
on 8 GB, and no real document has been scored.

A pipeline that ingests extracted text chunk by chunk needs one decision per chunk: keep it, hold it back, or leave it
alone because the validator has nothing to say about it. `validate` gives a full report (every cluster, every issue, every
line); `gate` gives that decision and the two numbers behind it, in about 150 bytes.

## The rules

1. **Letters.** A code point is a letter if `char::is_alphabetic()` is true for it, or it lies in one of the three
   Devanagari blocks: U+0900..U+097F (Devanagari), U+A8E0..U+A8FF (Devanagari Extended), U+1CD0..U+1CFF (Vedic Extensions).
   Matras, digits, the danda and the Vedic signs of the main block therefore count as letters; ASCII digits, spaces and
   punctuation do not.
2. **Devanagari share.** `devanagari_ppm` is the integer floor of `block letters × 1,000,000 ÷ letters`, where block letters
   are the letters inside the three blocks. With no letters it is 0.
3. **Script.** No letters: script `none`. `devanagari_ppm` below 500,000: script `other`. Otherwise `devanagari`. The boundary
   is exact: 250,000 Devanagari letters against 250,001 Latin ones is 499,999 ppm (`other`); against 250,000 it is 500,000
   (`devanagari`).
4. **Verdict.** Script `none` or `other`: verdict `not_scored`, `scored` false, `ppm` null. The chunk passes through marked
   "not scored"; no threshold turns it into `pass` or `hold`. Script `devanagari`: `ppm` is exactly `validate(text).score.ppm`
   (the gate computes it without building the per-cluster report, and a test pins the two equal), and the verdict is `pass`
   when `ppm >= threshold_ppm`, `hold` when it is below. A threshold equal to the score passes.
5. **Threshold.** A whole number of parts per million, 0 to 1,000,000; none given means `DEFAULT_GATE_THRESHOLD_PPM`, 975000.
   0 passes every scored chunk; 1,000,000 passes only a chunk with no issue at all. Anything else is refused (see below).
6. **Size.** Input over 4 MiB is refused with the same "too large" error as `validate`.

## The result

`glyphsift.gate/0.1`, compact JSON, fields in this order, no floating point, so native, Python and WASM print the same bytes:

```json
{"spec":"glyphsift.gate/0.1","scored":true,"script":"devanagari","devanagari_ppm":1000000,"ppm":750000,"threshold_ppm":975000,"verdict":"hold"}
{"spec":"glyphsift.gate/0.1","scored":false,"script":"other","devanagari_ppm":0,"ppm":null,"threshold_ppm":975000,"verdict":"not_scored"}
```

| Field | Meaning |
|---|---|
| `spec` | always `glyphsift.gate/0.1` |
| `scored` | true exactly when `script` is `devanagari` |
| `script` | `devanagari`, `other` or `none` |
| `devanagari_ppm` | Devanagari share of the letters, floored, 0 to 1,000,000 |
| `ppm` | the document score of the chunk (1,000,000 is clean), or `null` when not scored |
| `threshold_ppm` | the threshold that was applied, the default when none was given, also for a chunk that was not scored |
| `verdict` | `pass`, `hold` or `not_scored` |

## The calls

| Binding | Call | Refusals |
|---|---|---|
| Rust core | `gate(text: &str, threshold_ppm: Option<u32>) -> Result<GateReport, Error>`; `gate_to_canonical_json(&report)`; `parse_threshold(i64)` | `Error::InputTooLarge`, `Error::InvalidThreshold` |
| CLI | `glyphsift gate [--threshold-ppm N] FILE\|-` prints the JSON and exits 0 for every verdict | invalid UTF-8 is a usage error, exit 2; `N` outside 0..=1000000 or not a number, exit 2; a file that cannot be read, or input over 4 MiB, exit 1 |
| Python | `glyphsift.gate(text, threshold_ppm=None)` returns the JSON string; `glyphsift.DEFAULT_GATE_THRESHOLD_PPM`, `glyphsift.GATE_SPEC` | an unpaired surrogate raises `ValueError` (it cannot become a Rust `&str`); a threshold outside 0..1000000 raises `ValueError`, a non-integer one `TypeError`; over 4 MiB, `ValueError` |
| WASM, npm | `gate(text, threshold_ppm?)` returns the JSON string; `gate_spec()`, `default_gate_threshold_ppm()` | a string that is not well-formed (`String.prototype.isWellFormed()` is false) is a `TypeError` before the module is called, because wasm-bindgen would silently turn an unpaired surrogate into U+FFFD and the gate would answer for text the caller never had; a non-integer or non-number threshold is a `TypeError`, an integer outside 0..1000000 a `RangeError`; over 4 MiB, an `Error` saying "too large" |

`tests/determinism/gate/` holds 200 synthetic cases (the 13 determinism samples, hand-written boundary cases, seeded
mixtures; six of them ill-formed and one over 4 MiB) with the recorded answer for each: the native CLI, the Python wheel and the
WASM build must give the recorded bytes, or the word `rejected`, for every one (`scripts/determinism.sh`). The generator is
`scripts/make-gate-corpus.mjs`.

## The default threshold

The default is not a guess. `docs/score-vs-noise.csv` records the document score of the invented 288-line corpus corrupted by the
`mixed` family (every noise family on a disjoint partition of the sites) at seven noise levels and three seeds:

| `mixed`, seeds 1 to 3 | p=0 | p=0.01 | p=0.02 | p=0.05 | p=0.1 | p=0.2 | p=0.4 |
|---|---|---|---|---|---|---|---|
| lowest score_ppm | 1000000 | 998302 | 996897 | 991102 | 982847 | 965083 | 932111 |
| highest score_ppm | 1000000 | 998758 | 997061 | 992658 | 985156 | 970520 | 935924 |

Up to p=0.1 every seed scores at least 982847; from p=0.2 every seed scores at most 970520. A threshold in that gap separates "a
text with ordinary damage" from "a text with a lot", and the gap is 12,327 ppm wide. The default is 975000, the multiple of
5,000 nearest the middle of the gap (976,683): 7,847 ppm below the worst seed at p=0.1 and 4,480 ppm above the best seed at
p=0.2. `tests/gate.rs` re-derives the gap from the committed CSV and fails if 975000 is not in it, and checks that this page quotes
975000, 982847 and 970520.

What 975000 means for one chunk: the score is `1,000,000 − floor(penalty × 1000 ÷ clusters)`, and a flagged cluster costs the largest
weight among its issues (200 to 1000, `weights/devanagari.toml`). Staying at or above 975000 means the penalty is at most 25 per
cluster, that is, at most 25 weight-1000 clusters in a thousand. A chunk of 40 clusters passes with one weight-1000 cluster
flagged (exactly 975000) and is held with two; a chunk of 80 clusters passes with two and is held with three. A
weight-200 joiner slip on its own (the cheapest rule) passes in any chunk of eight clusters or more.

This is a structural threshold on invented text. It was not tuned on real documents or on a downstream model's answers, no real
document has been scored, and an owner with a sample set should expect to move it. The CLI's `--threshold-ppm`, the Python and
WASM argument and the demo's field exist for that.

## What a hold means

A hold says: this chunk of Devanagari text carries structural damage at or above the threshold, so it is probably text that
extraction garbled (matras without a consonant, doubled matras, stray viramas, control characters, a mixed-script cluster) and a
reader who asks a question should not be handed it as a source. In a pipeline the consequence is:

- the chunk is **not indexed** (it never reaches the vector store, so it cannot be retrieved or quoted);
- the reader is **told** how many chunks of the document were held and on which pages (the pipeline reason is `held_low_score`),
  so a missing answer is explained rather than silent;
- nothing is deleted: the held text stays in memory for that document until the reader closes it.

What a hold does not mean: that the text is wrong, or that the passed chunks are right. The validator is structural. It has no
dictionary and no language model; a well-formed nonsense word, an OCR confusion such as `ब` for `व`, and legacy-font text read
back as Latin letters all score clean (README, Limitations; seven noise families do not move the score at all). `pass` means
"no structural damage above the threshold was found", not "this text is correct".

`not_scored` is neither: the chunk is not mostly Devanagari (English, a table of digits, Tamil, Bengali, empty), so there is
nothing for the gate to judge. A pipeline passes such a chunk through and says that it was not scored. It must not read
`not_scored` as `pass` when it reports quality, and it must not hold it.

## Which noise to use to produce a hold

The dockit pipeline's test needs a noised Devanagari chunk that is held, with a clean one that passes. Two facts decide how to make
it, both measured here with the default threshold (`crates/glyphsift-core/tests/gate_noise.rs` regenerates and pins every number
below): the benchmark corpus corrupted at each level, split back into lines and cut into chunks of one, three and eight lines (the
sizes of a page cut into pieces), seeds 1 to 3; no chunk was ever `not_scored`, because the noise keeps well over half of the
letters Devanagari; and nothing was held at p=0.

**Hold counts out of 288 chunks of three lines** (96 chunks times three seeds, default threshold, by noise level p):

| family | p=0 | p=0.01 | p=0.02 | p=0.05 | p=0.1 | p=0.2 | p=0.4 |
|---|---|---|---|---|---|---|---|
| `mixed` | 0 | 3 | 4 | 24 | 81 | 168 | 274 |
| `matra_double` | 0 | 5 | 13 | 55 | 131 | 265 | 288 |
| `virama_insert` | 0 | 11 | 31 | 129 | 239 | 287 | 288 |
| `control_leak` | 0 | 33 | 108 | 237 | 285 | 288 | 288 |
| `mixed_script` | 0 | 3 | 22 | 100 | 194 | 274 | 288 |

**The `mixed` family by chunk size** (hold counts; the totals differ, so compare shares). A longer chunk's score sits closer to the
corpus mean, so it is held less often than a short one when the mean is above the threshold (p=0.1: 261 of 864 one-line chunks,
30%, against 14 of 108 eight-line chunks, 13%) and more often when the mean is below it (p=0.4: 694 of 864, 80%, against 104 of 108, 96%):

| chunk size | p=0 | p=0.01 | p=0.02 | p=0.05 | p=0.1 | p=0.2 | p=0.4 |
|---|---|---|---|---|---|---|---|
| 1 line (864 chunks) | 0 | 28 | 54 | 146 | 261 | 445 | 694 |
| 3 lines (288 chunks) | 0 | 3 | 4 | 24 | 81 | 168 | 274 |
| 8 lines (108 chunks) | 0 | 0 | 0 | 1 | 14 | 76 | 104 |

So the answer for D5 and for anyone building a test fixture: use `control_leak` at p=0.1 (or higher) or `virama_insert` at p=0.2
(or higher), on a chunk of about three lines. Those hold 285 of 288 and 287 of 288 chunks, and 288 of 288 one step higher. The
`mixed` family at p=0.4, the benchmark's headline, holds 274 of 288 (95%), so a `mixed` fixture can come out passing: whatever
family is used, **run the exact fixture through `glyphsift gate` and keep it only if the verdict is `hold`**, and commit that
verdict next to the fixture. A clean fixture should pass at p=0, and every clean chunk of the corpus does (0 of 864 held).

```sh
glyphsift corrupt --family control_leak --p 0.1 --seed 1 < clean-chunk.txt > noised-chunk.txt
glyphsift gate noised-chunk.txt        # "verdict":"hold" expected; check it, do not assume it
```

The noise generator rewrites the text, not the PDF: a fixture PDF whose text layer carries the noised text is a different file
from a noised page image, and the gate sees only the text layer.

## Limits

- Devanagari only. Marathi and Hindi pass; Tamil is planned for v0.2 (design note only, TD-18) and Bengali later; both are
  `not_scored` today. No claim is made about the quality of Hindi or any other Indic answer a model gives from gated text.
- Structural checks only, on synthetic text. See the README's Limitations for what the score cannot see.
- A chunk is judged alone: a table of mostly digits and Latin labels with one Devanagari word is `not_scored`, and a chunk that is
  half Latin and half Devanagari is scored on the whole chunk: its Latin letters count in the share but never in the penalty (a
  plain Latin letter is not a rule violation), so they raise the score of the chunk.
- The Devanagari share counts code points, not meaning: a chunk of Devanagari digits and dandas is `devanagari`.
- Every timing and memory figure in this repository is from the Apple M5 Pro, 48 GB; not measured on 8 GB.
