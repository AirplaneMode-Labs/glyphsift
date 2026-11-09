# Corruption generator design

Status: design only; implementation: Sprint 2 (23 Nov to 6 Dec 2026), alongside the validator.
Lowest-priority item of the lane; dropped before anything else if time is short.

## Purpose

The Sprint 2 "done when" is: **the glyphsift score falls monotonically as noise rises**, with the
chart in the README. The corruption generator takes a clean synthetic Devanagari corpus and applies
a named family of noise at a probability `p`, so the validator can be scored against text whose
true damage level is known. It also produces regression fixtures for every rule.

Out of scope: model-based scoring (a classifier or language model judging quality), real OCR runs,
and anything that needs scraped text.

## Clean corpus

`bench/corpus/clean.txt`: hand-written synthetic Hindi and Marathi sentences (target: 300 lines,
roughly 10k grapheme clusters) committed to the repository under Apache-2.0. Content is invented:
greetings, weather, numbers, dates, simple instructions. No text copied from any document, website
or dataset. Every line must pass the validator with zero issues before it is admitted (a test
enforces this once the validator exists).

## Noise families

Each family is a function `(cluster sequence, p, rng) -> cluster sequence`. For every eligible
site (defined per family) the generator draws `u` from the PRNG and applies the change when
`u < p`. `p` is the only parameter unless stated. Code-point classes are those of
`docs/devanagari-rules.md` section 2.

| Family | Eligible site | Change (Unicode mechanics) | Rules it should trigger | Parameters |
| --- | --- | --- | --- | --- |
| `matra_drop` | a cluster with a matra | delete the matra (`का` → `क`) | none directly (changes meaning, not structure); measures false-negative floor | `p` |
| `matra_swap` | a cluster with a matra | replace it with another matra drawn uniformly from the matra class (`कि` → `कु`) | none directly | `p` |
| `matra_double` | a cluster with a matra | duplicate the matra or append a second one (`का` → `काा`) | `double_matra` | `p` |
| `matra_detach` | a cluster with a matra | insert `U+0020` before the matra (`कि` → `क ि`) | `dependent_vowel_without_base` | `p` |
| `nukta_loss` | a consonant with nukta | remove `U+093C` (`ज़` → `ज`) | none directly | `p` |
| `nukta_spurious` | any consonant without nukta | insert `U+093C` after it (`क` → `क़`); with probability `q` place it after the matra instead (`का़`) or on a vowel/digit | `nukta_after_matra`, `nukta_on_non_consonant` | `p`, `q = 0.3` |
| `virama_delete` | a conjunct `C virama C` | remove `U+094D` (`क्ष` → `कष`) | none directly | `p` |
| `virama_insert` | a live consonant followed by a matra, or a cluster end | insert `U+094D` after the matra (`कि्`), after a vowel (`अ्`), or twice (`क््`) | `virama_after_matra`, `virama_without_consonant` | `p` |
| `bindu_swap` | anusvara or chandrabindu | swap `U+0902` ↔ `U+0901`; with probability `q` keep both (`कँं`) | `multiple_anusvara_like` (only the keep-both branch) | `p`, `q = 0.2` |
| `sign_order` | cluster with bindu/visarga and matra | move the bindu/visarga before the matra (`कां` → `कंा`); or swap visarga and anusvara (`कंः` → `कःं`) | `sign_before_matra`, `visarga_before_anusvara` | `p` |
| `reph_misplace` | `र् C` reph conjunct | move the `र्` after the consonant (`र्म` → `म्र`) or drop the virama leaving `रम` | none directly (orthographic, not structural); `virama_without_consonant` in a share of outputs | `p` |
| `joiner_inject` | any cluster boundary | insert `U+200D` or `U+200C` at a boundary that is not after a virama (`क‍क`, `‌क`) | `zwj_zwnj_misplaced` | `p` |
| `legacy_font` | any cluster | emulate an unmapped legacy-font (Kruti Dev / Shusha style) conversion: replace the cluster by its visual-order components, i.e. put a short-i matra before its consonant as a standalone `ि` (`कि` → `िक`), split reph to a trailing `Z`-like PUA code point (`U+F0D0`), map nukta forms to the base letter | `dependent_vowel_without_base`, `unexpected_code_point` | `p` |
| `ocr_confusion` | a consonant from the confusion table | replace by its confusable: `ब`↔`व`, `घ`↔`ध`, `भ`↔`म`, `ट`↔`ढ`, `ऱ`↔`र`, `ड`↔`ङ`, `य`↔`थ` | none directly; this family measures that structural validation alone cannot catch visually plausible errors (documented limitation) | `p` |
| `word_boundary` | a space | delete the space (`नमस्ते दुनिया` → `नमस्तेदुनिया`) or insert a space inside a cluster before a matra or virama (`क ्ष`) | `dependent_vowel_without_base`, `virama_without_consonant` | `p` |
| `digit_danda` | digit `१` or danda `।` | swap `U+0967` ↔ `U+0964` ↔ `U+007C` (ASCII bar) ↔ `U+0031`; `॥` → `।।` | none directly | `p` |
| `random_substitution` | any Devanagari code point | replace with a uniformly random code point from `U+0900..U+097F` | all rules, at random; the unstructured baseline | `p` |
| `mixed_script` | any Devanagari consonant or matra | replace the consonant with a Latin letter of similar shape (`A`, `e`, `o`) or the matra with its Bengali/Gurmukhi counterpart (`U+093E` → `U+09BE`, `U+0A3E`) | `mixed_script_in_cluster` | `p` |
| `control_leak` | any cluster boundary | insert `U+FEFF`, `U+200E`, `U+202E` or `U+0007` | `control_character` | `p` |

A `mixed` family applies every family above with the same `p` to disjoint random partitions of the
sites, giving the headline curve.

## Noise schedule

`p ∈ {0, 0.01, 0.02, 0.05, 0.1, 0.2, 0.4}` for every family. `p = 0` is the clean corpus and must
score 1.0 (no issues). Each `(family, p)` pair is generated for three seeds; the chart shows the
mean and the min/max band.

## Determinism

The PRNG is xorshift64\* seeded from the CLI `--seed` (u64, default 1). Code-point draws use
rejection sampling over the class tables so that adding a code point to a table does not shift
every later draw. Output files are named
`bench/results/<family>-p<p>-s<seed>.txt`, so a file name identifies its input exactly, and the
generator is pure (no clock, no environment, no OS randomness), like the validator.

## Evaluation protocol

For each `(family, p, seed)`:

1. Generate the corrupted corpus from `bench/corpus/clean.txt`.
2. Run `glyphsift check` over it; record `flagged_clusters / cluster_count` as the damage estimate
   and `1 - damage` as the score.
3. Record the recall per rule: of the sites the generator changed, how many produced the expected
   `IssueKind` in that cluster (the generator writes a sidecar `.sites.json` with the cluster
   indices and intended kinds).

Pass criteria for Sprint 2: for every family whose "rules it should trigger" column is non-empty,
score is non-increasing in `p` across the schedule for all three seeds, and the recall at
`p = 0.05` is at least 0.9. For families marked "none directly" the score curve is reported as a
documented limitation (structural validation does not see them), and no pass criterion applies.

## CLI shape

```sh
glyphsift corrupt --family matra_detach --p 0.05 --seed 7 < bench/corpus/clean.txt > out.txt
glyphsift corrupt --family mixed --p 0.1 --seed 1 --sites out.sites.json < clean.txt > out.txt
glyphsift corrupt --list-families
```

`--family` names one family or `mixed`; `--p` is a decimal in `[0, 1]`; `--seed` a u64; `--sites`
writes the sidecar. Exit 2 on bad arguments. The generator lives in `glyphsift-core::corrupt`
(behind a `corrupt` cargo feature so the WASM build does not carry it) and the chart is drawn by
`bench/chart.py` from the CSV the evaluation step writes; the PNG is committed to `docs/` with the
command that produced it in its caption.

## Out of scope

Model-based scoring (perplexity or classifier judgements), real OCR engines, real scanned pages,
and any corpus that is not hand-written in this repository.
