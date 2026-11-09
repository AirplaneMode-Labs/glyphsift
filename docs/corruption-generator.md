# Corruption generator

Status: implemented in Sprint 2 (`glyphsift-core::corrupt`, behind the non-default `corrupt` cargo
feature; `glyphsift corrupt` and `glyphsift bench` in the CLI). The WASM and Python builds do not
carry it.

## Purpose

The Sprint 2 "done when" is: **the glyphsift score falls monotonically as noise rises**, with the
chart in the README. The generator takes a clean synthetic Devanagari corpus and applies a named
family of noise at a probability `p`, so the validator can be scored against text whose true damage
level is known. It also produces regression fixtures for every rule.

Out of scope: model-based scoring (a classifier or language model judging quality), real OCR runs,
and anything that needs scraped text.

## Clean corpus

`bench/corpus/clean.txt`: hand-written synthetic Hindi and Marathi sentences (288 lines at the time
of writing, more than 5,000 grapheme clusters), committed under Apache-2.0. Content is invented:
greetings, weather, numbers, dates, simple instructions. No text copied from any document, website
or dataset. Every line validates with zero issues (`tests/corrupt.rs` enforces it), nuktas are
written decomposed (`U+0915 U+093C`, never `U+0958`), and the file uses LF line endings without a
BOM. Any change to the corpus after the first benchmark run is listed in `CHANGELOG.md` with its
reason.

## Sites and coupling

The generator splits the clean text into the same UAX #29 clusters the validator uses. Every
cluster is a candidate **site**; site `i` is the `i`-th cluster of the clean input. For a single
family a site is *eligible* when the cluster satisfies the family's "eligible site" column below
(decided from the clean text alone, never from the random draw); under `mixed`, site `i` belongs to
family `ALL[splitmix64(seed ^ i) mod 19]` and is eligible if the cluster satisfies that family's
column.

The draws are counter-based, so a site's fate depends only on `(seed, family, i)` and never on the
other sites or on `p`:

- `u_i = xorshift64*(splitmix64(seed ^ fnv1a64(family) ^ i))`, one output from that state;
  `fnv1a64("mixed")` stands in for the family name under `mixed`.
- site `i` is corrupted iff `((u_i >> 11) * 1_000_000) >> 53 < p_ppm`, evaluated in 128-bit integer
  arithmetic. `p_ppm` is `p` in parts per million, so there is no floating point anywhere.
  Because `u_i` does not depend on `p`, the set of corrupted sites at one `p` is a subset of the
  set at any larger `p`.
- what a corrupted site becomes comes from a second stream,
  `xorshift64*(splitmix64(splitmix64(seed ^ fnv1a64(family) ^ i) ^ 1))`, which also does not depend
  on `p`: a site corrupted at two values of `p` is corrupted identically at both.
- code-point draws use rejection sampling over the Devanagari block (seven bits per draw, accepted
  if the code point is in the wanted class), so adding a code point to a class table does not shift
  every later draw.

`p` is a decimal string converted to ppm: digits, optionally a dot and one to six more digits, with
a value in `[0, 1]`; anything else is refused (exit 2 on the CLI). `p = 0` is the identity.

## Noise families

Each family is a function from one eligible site to a replacement string. Code-point classes are
those of `docs/devanagari-rules.md` section 2. A site that corrupts to a cluster no rule can see
declares no expected rule; the sidecar records what each site is *expected* to trigger so that
recall can be measured.

| Family | Eligible site | Change (Unicode mechanics) | Rules it should trigger | Parameters |
| --- | --- | --- | --- | --- |
| `matra_drop` | a cluster with a matra | delete the first matra (`का` → `क`) | none directly (changes meaning, not structure); measures the false-negative floor | `p` |
| `matra_swap` | a cluster with a matra | replace the first matra with another matra drawn uniformly from the matra class (`कि` → `कु`) | none directly | `p` |
| `matra_double` | a cluster with a matra | insert a second matra right after the first: a copy of it or a random matra (`का` → `काा`) | `double_matra` | `p` |
| `matra_detach` | a cluster with a matra | insert `U+0020` before the first matra (`कि` → `क ि`) | `dependent_vowel_without_base` | `p` |
| `nukta_loss` | a cluster with a nukta | remove the first `U+093C` (`ज़` → `ज`) | none directly | `p` |
| `nukta_spurious` | a consonant without a nukta, or an independent vowel or digit | on a vowel or digit, insert `U+093C` after it; on a consonant insert it after the consonant (valid), or with probability `q` after the first matra instead (`का़`) | `nukta_after_matra`, `nukta_on_non_consonant` | `p`, `q = 0.3` |
| `virama_delete` | a conjunct, `C virama C` | remove the first `U+094D` that precedes a consonant (`क्ष` → `कष`) | none directly | `p` |
| `virama_insert` | a cluster with a matra, an independent vowel, or a consonant | insert `U+094D` after the first matra (`कि्`), after the vowel (`अ्`), or twice after the last consonant (`क््`) | `virama_after_matra`, `virama_without_consonant` | `p` |
| `bindu_swap` | a cluster with anusvara or chandrabindu | swap `U+0902` and `U+0901`; with probability `q` keep both (`कँं`) | `multiple_anusvara_like` (only the keep-both branch) | `p`, `q = 0.2` |
| `sign_order` | a cluster with a bindu or visarga after its matra, or with a bindu followed by a visarga | move the bindu or visarga before the matra (`कां` → `कंा`), or swap a bindu and the visarga after it (`कंः` → `कःं`) | `sign_before_matra`, `visarga_before_anusvara` | `p` |
| `reph_misplace` | a cluster that starts `र् C` | move the `र्` behind the consonant (`र्म` → `म्र`) or drop the virama (`रम`); both are valid clusters | none directly (orthographic, not structural) | `p` |
| `joiner_inject` | any cluster boundary not after a virama (the boundary before the first cluster included) | insert `U+200D` or `U+200C` (`क‍क`, `‌क`) | `zwj_zwnj_misplaced` | `p` |
| `legacy_font` | a cluster that starts `र् C`; or a word-initial syllable with a short-i matra; or a cluster with a nukta | emulate an unmapped legacy-font (Kruti Dev / Shusha style) conversion: drop the reph and append the private-use code point `U+F0D0`; put the short-i matra before its consonant as a standalone `ि` (`कि` → `िक`); drop the nukta. The short-i is moved only at the start of a word: mid-word it would attach to the previous consonant, which no structural rule can see | `dependent_vowel_without_base`, `unexpected_code_point` | `p` |
| `ocr_confusion` | a cluster whose first code point is in the confusion table | replace it by its confusable: `ब`↔`व`, `घ`↔`ध`, `भ`↔`म`, `ट`↔`ढ`, `ऱ`↔`र`, `ड`↔`ङ`, `य`↔`थ` | none directly; this family measures that structural validation alone cannot catch visually plausible errors (documented limitation) | `p` |
| `word_boundary` | a space, or a cluster with a matra or a virama | delete the space (`नमस्ते दुनिया` → `नमस्तेदुनिया`), or insert a space before the first matra or virama (`कि` → `क ि`, `क्ष` → `क ्ष`) | `dependent_vowel_without_base`, `virama_without_consonant` | `p` |
| `digit_danda` | a cluster that is one Devanagari digit or danda | digit to the ASCII digit, `।` or the ASCII bar; `।` to the ASCII bar or `1`; `॥` to `।।` | none directly | `p` |
| `random_substitution` | a cluster with any code point in `U+0900..U+097F` | replace one such code point, chosen uniformly, with a different code point drawn uniformly from the block | all rules, at random; the unstructured baseline | `p` |
| `mixed_script` | a consonant that carries a nukta, virama, matra or sign | replace the consonant with a Latin letter (`A`, `e`, `o`), or the first matra with its Bengali or Gurmukhi counterpart where Unicode has one (`U+093E` → `U+09BE`, `U+0A3E`) | `mixed_script_in_cluster` | `p` |
| `control_leak` | any cluster boundary except the one at the start of the text (a BOM at offset 0 is valid) | insert `U+FEFF`, `U+200E`, `U+202E` or `U+0007` | `control_character` | `p` |

`mixed` applies every family above with the same `p` to a disjoint partition of the sites (each
site belongs to exactly one family, see "Sites and coupling"), giving the headline curve.

A family is **triggering** when its "rules it should trigger" column names rules or describes a
random mixture, and **none directly** otherwise. `Family::strength()` and `Family::triggers()` in
`corrupt.rs` carry the same classification; a test parses this table and fails if the two drift.
Twelve families are triggering and seven are none directly.

## Noise schedule

`p ∈ {0, 0.01, 0.02, 0.05, 0.1, 0.2, 0.4}` for every family. `p = 0` is the clean corpus and must
score 1.0 (no issues). Each `(family, p)` pair is generated for seeds 1, 2 and 3; the chart shows
the mean and the min/max band of the mixed family.

## Determinism

The generator is pure: no clock, no environment, no operating-system randomness, no floating point,
no hash-based collections. The PRNG is xorshift64\*; seeds are u64 (`--seed`, default 1). The same
`(clean text, family, p, seed)` always gives byte-identical output.

## Evaluation protocol

For each `(family, p, seed)`, `glyphsift bench`:

1. generates the corrupted corpus from `bench/corpus/clean.txt`;
2. runs the validator over it and records `cluster_count`, `flagged_clusters` and the document
   `score_ppm` (the score of `docs/devanagari-rules.md` section 6);
3. computes recall: of the corrupted sites that declare an expected rule, the share (in ppm) for
   which the output cluster that carries the damage has an issue of one of the declared kinds. The
   CSV cell is empty when no site declares a rule (every `none directly` family, `p = 0`, and
   `random_substitution`).

Pass criteria, checked by `glyphsift bench` (exit 1 on any violation) and stated in the README:

1. the mixed-family mean score, over the seeds, falls strictly at every consecutive step of the
   schedule from `p = 0` to `p = 0.4`;
2. the mixed family is non-increasing in `p` for each seed;
3. every triggering family is non-increasing in `p` for each seed;
4. `score_ppm` is `1_000_000` at `p = 0` for every row.

Recall at `p = 0.05` is at least 0.9 for every family that declares a rule (a test enforces it on
seeds 1 to 3); a shortfall would be listed under Limitations in the README. For `none directly`
families the curve is reported as a documented limitation (structural validation does not see
them) and no pass criterion applies.

## CLI shape

```sh
glyphsift corrupt --family matra_detach --p 0.05 --seed 7 < bench/corpus/clean.txt > out.txt
glyphsift corrupt --family mixed --p 0.1 --seed 1 --sites out.sites.json < clean.txt > out.txt
glyphsift corrupt --list-families
glyphsift bench --corpus bench/corpus/clean.txt --seeds 1,2,3 \
    --csv docs/score-vs-noise.csv --svg docs/score-vs-noise.svg
glyphsift bench --verify docs/score-vs-noise.csv     # re-check the criterion on an existing CSV
```

`--family` names one family or `mixed`; `--p` is a decimal in `[0, 1]`; `--seed` a u64; `--sites`
writes the sidecar: compact JSON `{"family","seed","p_ppm","sites":[{"source","cluster","family",
"kinds"}]}` where `source` is the clean cluster index and `cluster` the index in the corrupted
output of the cluster that carries the damage. Exit 2 on bad arguments, 1 on an I/O or UTF-8 error.
The chart is drawn by the CLI itself from the same numbers it writes to the CSV: a deterministic SVG
(integer coordinates, fixed palette, no timestamp, no script) committed as `docs/score-vs-noise.svg`.

## Out of scope

Model-based scoring (perplexity or classifier judgements), real OCR engines, real scanned pages,
and any corpus that is not hand-written in this repository.
