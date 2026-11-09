# Devanagari grapheme-cluster rules

Status: specification complete; implementation: Sprint 2 (23 Nov to 6 Dec 2026). The case table
`crates/glyphsift-core/tests/cases/devanagari.toml` is the executable form of this document; where
the two disagree, fix the one that is wrong and add a case.

## 1. Segmentation

Input is split into **UAX #29 extended grapheme clusters** using `unicode-segmentation` 1.13.3
(`UnicodeSegmentation::grapheme_indices(text, true)`), nothing more and nothing less. This includes
the Unicode 15.1 rule GB9c, which keeps `consonant virama consonant` sequences together, so `क्ष`,
`स्ते` and `र्म` are single clusters, while `क्‌ष` (ZWNJ after the virama) is two, because ZWNJ is
not `InCB=Extend`. Control characters (`Grapheme_Cluster_Break=Control`: C0/C1 controls, most
`Cf` format characters, `U+FEFF`) always form their own cluster. A spacing matra after a space
joins the space's cluster (` ा`), which is why "matra after space" is a cluster-level finding.

The validator does **not** normalise. Input is judged as given. `U+0958..U+095F` (precomposed
nukta consonants, composition exclusions) are classed as consonants that already carry a nukta.

Every rule below is evaluated **within one cluster**; the validator keeps no state between clusters
in 0.1. Word- and document-level signals are a later layer.

## 2. Code-point tables

| Class | Code points |
| --- | --- |
| Consonant `C` | `U+0915..U+0939` (क..ह), `U+0958..U+095F` (precomposed nukta forms क़..य़; carry an implicit nukta), `U+0978..U+097F` (ॸ..ॿ) |
| Nukta | `U+093C` |
| Virama | `U+094D` |
| Matra (dependent vowel sign) | `U+093A`, `U+093B`, `U+093E..U+094C` (ा..ौ), `U+094E`, `U+094F`, `U+0955..U+0957`, `U+0962`, `U+0963` |
| Bindu (anusvara-like) | `U+0900` (inverted chandrabindu), `U+0901` (chandrabindu), `U+0902` (anusvara) |
| Visarga | `U+0903` |
| Independent vowel `V` | `U+0904..U+0914` (ऄ..औ), `U+0960`, `U+0961` (ॠ ॡ), `U+0972..U+0977` (ॲ..ॷ) |
| Digit | `U+0966..U+096F` (०..९) |
| Danda | `U+0964` (।), `U+0965` (॥) |
| Avagraha | `U+093D` (ऽ) |
| Om | `U+0950` (ॐ) |
| Vedic sign | `U+0951..U+0954` (udatta, anudatta, grave, acute) |
| Abbreviation / dot | `U+0970` (॰), `U+0971` (ॱ) |
| Joiner | `U+200D` ZWJ, `U+200C` ZWNJ |
| Allowed control | `U+0009` TAB, `U+000A` LF, `U+000D` CR |
| Control (flagged) | other `Cc` (`U+0000..U+001F`, `U+007F..U+009F`); bidi controls `U+200E`, `U+200F`, `U+202A..U+202E`, `U+2066..U+2069`; `U+FEFF` after offset 0 |
| Unexpected (flagged) | `U+FFFD`; private use `U+E000..U+F8FF`, `U+F0000..U+10FFFF`; unassigned and noncharacters; any code point in `U+0900..U+097F`, `U+A8E0..U+A8FF` (Devanagari Extended) or `U+11B00..U+11B5F` (Devanagari Extended-A) that is not in a row above |

Standalone (never flagged on their own): digits, danda, avagraha, om, abbreviation sign, high
spacing dot, space and other `Zs`, punctuation, Latin and other-script letters without Devanagari
marks, emoji and symbols.

"Devanagari mark" below means any of: nukta, virama, matra, bindu, visarga, Vedic sign. "Other
script" means a base letter (`L*` general category) outside `U+0900..U+097F`, `U+A8E0..U+A8FF`,
`U+11B00..U+11B5F`; a combining mark from another Indic block (for example Bengali `U+09BE`) on a
Devanagari base is also "other script".

## 3. Cluster grammar

A cluster is **valid** when it matches one of:

```
syllable   := ( C nukta? virama (ZWJ | ZWNJ)? )*  C nukta? matra? bindu? visarga?  vedic*
dead       := ( C nukta? virama (ZWJ | ZWNJ)? )*  C nukta? virama (ZWJ | ZWNJ)?    vedic*
vowel      := V bindu? visarga? vedic*
standalone := digit | danda | avagraha | om | abbreviation | dot | Zs | punctuation
            | other-script base without Devanagari marks | emoji/symbol | TAB | LF | CR
```

Notes: at most one matra; at most one bindu; bindu before visarga; nukta directly after its
consonant; virama directly after a consonant (or after its nukta); ZWJ/ZWNJ only directly after a
virama; a trailing virama (dead consonant) is valid; `र्‍` (ra virama ZWJ, the eyelash reph) is the
`dead`/`syllable` grammar with ZWJ and is valid.

## 4. Rules

Each `IssueKind` is one rule. A cluster may produce several issues; they are reported in code-point
order. `code_point` names the offending code point as `U+XXXX`.

| IssueKind | Fires when | Example (case name) |
| --- | --- | --- |
| `dependent_vowel_without_base` | a matra whose preceding code point is not a live consonant (cluster start, after space, after a dead consonant `C virama (ZWJ/ZWNJ)?`, after a digit, danda or sign) | `matra_alone_i`, `dead_consonant_matra`, `matra_on_digit` |
| `stray_combining_mark` | bindu, visarga, nukta or Vedic sign with no base in its cluster (cluster start, or after a space) | `anusvara_alone`, `visarga_after_space`, `nukta_alone` |
| `double_matra` | a second matra in the cluster | `double_matra_aa`, `double_matra_i_e` |
| `double_nukta` | a second nukta on the same consonant, counting the implicit nukta of `U+0958..U+095F` | `double_nukta`, `nukta_on_precomposed` |
| `nukta_after_matra` | nukta after a matra, bindu or visarga in the cluster | `nukta_after_matra` |
| `nukta_on_non_consonant` | nukta directly after an independent vowel, digit, danda or sign (a base exists but is not a consonant) | `nukta_on_vowel`, `nukta_on_digit` |
| `virama_without_consonant` | virama at cluster start, directly after a vowel, after another virama, or after a nukta that is not on a consonant | `virama_alone`, `virama_on_vowel`, `double_virama` |
| `virama_after_matra` | virama directly after a matra (the syllable already has its vowel) | `virama_after_matra`, `two_issues_one_cluster` |
| `sign_before_matra` | bindu or visarga followed by a matra in the same cluster | `sign_before_matra_anusvara`, `sign_before_matra_visarga` |
| `multiple_anusvara_like` | a second bindu (anusvara, chandrabindu, inverted chandrabindu) in the cluster | `double_anusvara`, `chandrabindu_anusvara` |
| `visarga_before_anusvara` | visarga followed by a bindu | `visarga_before_anusvara` (`कंः` is valid) |
| `vowel_sign_on_independent_vowel` | a matra directly after an independent vowel | `matra_on_independent_a`, `matra_on_independent_i` |
| `zwj_zwnj_misplaced` | ZWJ or ZWNJ whose preceding code point is not a virama | `zwj_between_consonants`, `zwnj_at_start`, `zwj_after_matra` |
| `mixed_script_in_cluster` | the cluster's base is from another script and carries a Devanagari mark, or a Devanagari base carries a mark from another Indic block. Suppresses the other mark rules for that cluster (one issue, the root cause). | `latin_base_devanagari_matra`, `bengali_mark_on_devanagari`, `tamil_base_devanagari_virama` |
| `unexpected_code_point` | any code point in the "Unexpected" row of the table | `replacement_char`, `private_use`, `private_use_legacy_font` |
| `control_character` | any code point in the "Control (flagged)" row | `control_bell`, `bidi_control`, `bom_mid_text`, `nul` |

Precedence: `mixed_script_in_cluster` is exclusive for its cluster. `control_character` and
`unexpected_code_point` clusters are single code points under UAX #29 and produce exactly that one
issue. Otherwise every rule that fires is reported.

Decisions worth recording:

- `क्ा` (consonant, virama, matra) is `dependent_vowel_without_base`, not a virama error: after a
  virama the grammar expects a consonant, so the matra is the misplaced element.
- `कँं` is `multiple_anusvara_like` once, on the second bindu.
- `अ + ा` is flagged even though some legacy keyboards produce it; `U+0906` is the letter.
  `ऑ`, `ऍ`, `ॲ` are atomic code points, so there is no legitimate `अ + matra` sequence to exempt.
- ZWJ/ZWNJ after a virama are valid at the end of a cluster or word (half form request), following
  Unicode Standard chapter 12.1.

## 5. Public API shape

```rust
pub fn validate(text: &str) -> Result<Report, Error>;   // Sprint 1: Err(Unimplemented)
pub fn clusters(text: &str) -> Vec<Cluster>;            // UAX #29 clusters with byte offsets
pub fn to_canonical_json(report: &Report) -> String;

pub struct Report  { spec: "glyphsift.report/0.1", script: "devanagari", code_points, clusters: Vec<Cluster>, issues: Vec<Issue>, summary: Summary }
pub struct Cluster { index, text, start, end, code_points: Vec<"U+XXXX"> }
pub struct Issue   { kind: IssueKind, cluster: usize, code_point: Option<"U+XXXX"> }
pub struct Summary { cluster_count, issue_count, flagged_clusters }
```

CLI: `glyphsift check <file|->` prints the report; Python: `glyphsift.validate(text) -> str`;
WASM: `validate(text) -> string` (throws on error). Scores (a 0..1 per-document figure) are a
Sprint 2 addition on top of the counts and will be integers in basis points, never floats, so the
canonical JSON stays bit-identical across runtimes.

## 6. Canonical JSON rule

`serde_json::to_string` (compact, no whitespace), struct fields in declaration order, every
collection a `Vec` in input order, strings escaped exactly as JSON.stringify does (`"`, `\`,
`U+0000..U+001F`; `/` not escaped), no floating-point values anywhere. `serde_json` is built without
`preserve_order`. This is what makes the native, Python and WASM outputs byte-identical.

## 7. Known gaps (to revisit in Sprint 2)

- Devanagari Extended cantillation marks (`U+A8E0..U+A8F1`) are currently "unexpected"; Vedic text
  will need them classed as Vedic signs.
- `U+094E` and `U+094F` (prishthamatra e, aw) are matras here; their rendering order differs from
  other matras and may need a dedicated rule.
- Nukta on `र` to give `ऱ` (Marathi) and on `ळ` to give `ऴ` are valid and covered by the general
  nukta rule; no special-casing yet.
