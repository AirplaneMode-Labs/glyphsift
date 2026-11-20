# What glyphsift measures

Status: written in Sprint 6 (19 Nov 2026) and re-read against the committed files in Sprint 7 (20 Nov 2026), for glyphsift 0.1.3, untagged and unpublished. Sprint 7 changed no number on this page: the benchmark CSV, the gate and the determinism corpus are byte-identical to Sprint 6. This page is short on purpose and is
the only text about glyphsift's results that anyone outside this repository should quote. Every number on it is read from a
committed file by `tests/docs_numbers.py`, and the file and the command that produce it are named next to it. Anything not on
this page is not claimed.

## What the score is

glyphsift looks at extracted Devanagari text and asks one structural question: inside each grapheme cluster, are the code points in an
order and combination the script allows (a matra after a consonant, a virama before a consonant, a nukta in the right place, and so
on)? It applies 16 structural rules (`docs/devanagari-rules.md`). A flagged cluster costs the largest weight among its issues, and the
document score is `1,000,000` minus the penalty per cluster, in parts per million (ppm): 1,000,000 is clean, lower is worse. There is no
dictionary, no language model and no network. The output is integers only, so it can be byte-identical across runtimes.

It measures broken structure. It does not measure whether the words are the right words: a well-formed nonsense word scores clean,
and so does a plausible look-alike letter swap.

## The score falls as noise rises

`docs/score-vs-noise.csv` holds 420 rows: 20 noise families, 7 noise levels and 3 seeds, produced by corrupting the invented, 288-line
corpus `bench/corpus/clean.txt` with the seeded generator in `docs/corruption-generator.md`. The noise levels are
p=0, p=0.01, p=0.02, p=0.05, p=0.1, p=0.2, p=0.4.

- Monotonic: 0 of 60 (family, seed) series rise as p rises, and the score is 1,000,000 at p=0 in every row.
- Re-check without regenerating: `glyphsift bench --verify docs/score-vs-noise.csv` prints `verdict: PASS` (build it with
  `cargo build --locked --release -p glyphsift-cli`).
- Regenerate the file: `glyphsift bench --corpus bench/corpus/clean.txt --seeds 1,2,3 --csv docs/score-vs-noise.csv --svg docs/score-vs-noise.svg`.

The `mixed` family (every noise family at once, on disjoint sites), the lowest and highest score over the three seeds:

| mixed | p=0 | p=0.01 | p=0.02 | p=0.05 | p=0.1 | p=0.2 | p=0.4 |
|---|---|---|---|---|---|---|---|
| lowest score_ppm | 1,000,000 | 998,302 | 996,897 | 991,102 | 982,847 | 965,083 | 932,111 |
| highest score_ppm | 1,000,000 | 998,758 | 997,061 | 992,658 | 985,156 | 970,520 | 935,924 |

The blind spot, stated in the same file: 7 families never move the score (every row is 1,000,000): `digit_danda`, `matra_drop`,
`matra_swap`, `nukta_loss`, `ocr_confusion`, `reph_misplace`, `virama_delete`. They change the text without breaking a structural rule,
so structural validation cannot see them. Part of the monotone fall is by construction (the damaged sites at one level are a subset of
those at the next, and a flagged cluster only adds penalty), so the curve shows that the score responds to injected structural damage,
not that it predicts the quality of any real document.

## The gate

`gate(text, threshold_ppm)` turns the score into one decision per chunk: `pass`, `hold` or `not_scored` (text that is not mostly
Devanagari is passed through unjudged). The default threshold is 975000 ppm (`DEFAULT_GATE_THRESHOLD_PPM` in
`crates/glyphsift-core/src/gate.rs`; the rules are in `docs/gate.md`). It sits in the gap between the worst `mixed` seed at p=0.1
(982,847) and the best at p=0.2 (970,520): the gap is 12,327 ppm wide, and the threshold is 7,847 ppm below the worst seed at p=0.1
and 4,480 ppm above the best seed at p=0.2. It was derived from the invented corpus, not from real documents, and a user with a
sample set should expect to move it.

## Native, Python and WASM give the same bytes

The same inputs go through the Rust command-line build, the Python wheel and the WebAssembly build, and the output is compared byte for byte
with bytes committed in the repository: 13 sample texts (`tests/determinism/samples`, reports in `tests/determinism/expected`) and 200 gate cases
(`tests/determinism/gate/cases.jsonl`, answers in `tests/determinism/gate/expected.jsonl`). Of the 200 gate cases the recorded answers are
77 pass, 92 hold, 24 not_scored and 7 rejected (an ill-formed string or input over 4 MiB, which every build must refuse). The command is
`scripts/determinism.sh`; it fails on the first byte that differs.

## Limits

- Devanagari only. Other scripts are passed through as text and are never flagged. Tamil is a design note, not code.
- Unpublished: nothing is on npm, PyPI or crates.io, no package names are reserved and no release is tagged.
- Synthetic text only: no real document has been scored, and the benchmark is invented text with invented noise.
- No claim about Hindi answer quality, about any downstream system, or about any organisation's data.
- Structural checks only: the 7 blind-spot families above score clean by design.
- The machine is the development Mac (Apple M5 Pro, 48 GB). The 8 GB laptop figure is not measured on 8 GB, and this page gives no
  throughput figure at all.

## Check this page

`python3 -I tests/docs_numbers.py` re-reads every number above from the files named here and fails if one differs; change a value in
`docs/score-vs-noise.csv` and it fails.
