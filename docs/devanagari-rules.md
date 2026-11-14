# Devanagari grapheme-cluster rules

Status: implemented in Sprint 2 (`crates/glyphsift-core/src/tables.rs`, `src/rules.rs`,
`src/score.rs`) and revised in Sprint 3 for glyphsift 0.1.0: `zwj_zwnj_misplaced` is restricted to
Devanagari-based clusters (BUG-T2-S2-07), and tag characters and non-Indic combining marks in
Devanagari clusters are flagged (BUG-T2-S2-15). The rule count stays sixteen and no weight changed.
The case table `crates/glyphsift-core/tests/cases/devanagari.toml` is the executable form of this
document: every case passes, and where the two disagree, fix the one that is wrong and add a case first.

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
| Joiner | `U+200D` ZWJ, `U+200C` ZWNJ (Cf format characters, not combining marks) |
| Tag character | `U+E0001` and `U+E0020..U+E007F`: invisible Cf code points; flagged as unexpected in a Devanagari-based cluster or when they start a cluster (below) |
| Allowed control | `U+0009` TAB, `U+000A` LF, `U+000D` CR |
| Control (flagged) | other `Cc` (`U+0000..U+001F`, `U+007F..U+009F`); bidi controls `U+200E`, `U+200F`, `U+202A..U+202E`, `U+2066..U+2069`; `U+FEFF` after offset 0 |
| Foreign combining mark | any other Mn, Mc or Me code point: another Indic block (for example Bengali `U+09BE`), or non-Indic such as `U+0301`, `U+20D7`, `U+20E3`, `U+1D165`. Not foreign: Devanagari, Devanagari Extended `U+A8E0..U+A8FF`, Devanagari Extended-A `U+11B00..U+11B5F`, Vedic Extensions `U+1CD0..U+1CFF`, the variation selectors `U+FE00..U+FE0F` and `U+E0100..U+E01EF`, ZWJ and ZWNJ |
| Unexpected (flagged) | `U+FFFD`; private use `U+E000..U+F8FF`, `U+F0000..U+10FFFF`; unassigned and noncharacters; any code point in `U+0900..U+097F`, `U+A8E0..U+A8FF` (Devanagari Extended) or `U+11B00..U+11B5F` (Devanagari Extended-A) that is not in a row above; a tag character in a Devanagari-based cluster or starting its cluster |

Implementation: each row is a sorted `const` slice of inclusive ranges searched by binary search
(`tables.rs`); unit tests prove the slices are sorted and disjoint and that the Devanagari block
`U+0900..U+097F` has no gap. "Unassigned" and the letter and mark classes of other scripts come from
the `unicode-general-category` crate (Unicode 16.0 tables compiled in, so every build agrees). A BOM
(`U+FEFF`) is an allowed control at byte offset 0 only, and the CRLF pair is one cluster of two
allowed controls.

Standalone (never flagged on their own): digits, danda, avagraha, om, abbreviation sign, high
spacing dot, space and other `Zs`, punctuation, Latin and other-script letters without Devanagari
marks, emoji and symbols.

**Devanagari-based clusters.** A cluster is Devanagari-based when its first code point is
Devanagari-class: a letter, digit, danda, avagraha, om, abbreviation sign or any Devanagari combining
mark in `U+0900..U+097F` (not a joiner, a control, a space or anything from another script). The
parser computes this once per cluster (`Slot::devanagari_base`). Two rules look at it:

- **Joiners (rule 13, BUG-T2-S2-07).** A ZWJ or ZWNJ is flagged only when its preceding code point is
  not a virama **and** the cluster is Devanagari-based **or** the joiner starts its cluster (the very
  start of the text, or after a line terminator or other control, where UAX #29 GB4 makes it a cluster
  of its own). So a joiner inside an emoji ZWJ sequence (a family emoji, the rainbow flag), a Persian
  word written with a ZWNJ, or Latin or Arabic text with a ZWJ is not flagged: the cluster's first code
  point is an emoji or a letter of another script. Still flagged: consonant + ZWJ without a virama, a
  second joiner after a virama's joiner, a lone joiner. By the same rule a joiner that joins a space's
  cluster (`" " + ZWJ`) is **not** flagged, since a space is not Devanagari-class and the joiner does not
  start the cluster; this is a deliberate consequence of the rule, and the benchmark's
  `joiner_inject` family no longer expects rule 13 at such a site.
- **Tag characters (rule 15, BUG-T2-S2-15).** A Unicode tag character (`U+E0001`, `U+E0020..U+E007F`)
  is invisible and is Extend for UAX #29 (except `U+E0001`, which is a Control and always its own
  cluster), so it joins the cluster before it. In a Devanagari-based cluster, or starting its own
  cluster, it is `unexpected_code_point`: a Devanagari consonant followed by `U+E0041` no longer scores
  clean. A tag in a non-Devanagari cluster (the England flag, black flag plus tag letters) is part of
  an emoji tag sequence and is not flagged; so is a tag after a Latin letter (hidden text outside
  Devanagari clusters is out of scope for this validator). A tag that starts a cluster belongs to no
  emoji tag sequence, so it is flagged: this is also how `U+E0001` is caught.

**Foreign combining marks (rule 14, BUG-T2-S2-15).** A combining mark (general category Mn, Mc or Me)
that is not Devanagari, not Devanagari Extended or Extended-A, not a Vedic Extensions mark and not a
variation selector, on a Devanagari-based base (consonant, nukta consonant, independent vowel, digit,
danda, avagraha, om, abbreviation sign) is `mixed_script_in_cluster`, the same issue as a Bengali mark
on a Devanagari base always was: `क` + `U+0301`, `क` + `U+20D7`, `१` + `U+0301` are flagged, and the
cluster reports that one issue only (rule 14 is exclusive). `e` + `U+0301`, a keycap sequence and a
space with a mark are not Devanagari-based and are not flagged. Variation selectors are not flagged on
any base, and Vedic Extensions marks are not flagged on a Devanagari base. A combining grapheme joiner
(`U+034F`, Mn) is a foreign mark. Documented limit: a cluster that starts with a Devanagari combining
mark (a matra at the start of a line) is judged by the Devanagari rules for that mark and not by rule
14.

"Devanagari mark" below means any of: nukta, virama, matra, bindu, visarga, Vedic sign. "Other
script" means a base letter (`L*` general category) outside `U+0900..U+097F`, `U+A8E0..U+A8FF`,
`U+11B00..U+11B5F`; a foreign combining mark (see above: another Indic block such as Bengali
`U+09BE`, or a non-Indic mark such as `U+0301`) on a Devanagari base is also "other script".

## 3. Cluster grammar

A cluster is **valid** when it matches one of:

```
syllable   := ( C nukta? virama (ZWJ | ZWNJ)? )*  C nukta? matra? bindu? visarga?  vedic*
dead       := ( C nukta? virama (ZWJ | ZWNJ)? )*  C nukta? virama (ZWJ | ZWNJ)?    vedic*
vowel      := V bindu? visarga? vedic*
standalone := digit | danda | avagraha | om | abbreviation | dot | Zs | punctuation
            | other-script base without Devanagari marks | emoji/symbol | TAB | LF | CR
```

Implementation: `rules.rs` parses each cluster once, left to right, in time linear in its length.
For every code point it records what the code point attaches to (`Host`: nothing yet, a live
consonant, a dead consonant, an independent vowel, or a base that cannot carry marks such as a space,
digit or danda) and what the cluster has seen since the current consonant or vowel started (matras,
bindus, a visarga, nuktas including the implicit one of `U+0958..U+095F`). Each rule below is then a
small pure predicate over that record. A new consonant after a virama starts a fresh record, so
`क्ष` and `स्ते` are judged as one conjunct.

Notes: at most one matra; at most one bindu; bindu before visarga; nukta directly after its
consonant; virama directly after a consonant (or after its nukta); ZWJ/ZWNJ only directly after a
virama (in a Devanagari-based cluster; a joiner in another script's cluster is that script's business); a trailing virama (dead consonant) is valid; `र्‍` (ra virama ZWJ, the eyelash reph) is the
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
| `zwj_zwnj_misplaced` | ZWJ or ZWNJ whose preceding code point is not a virama, in a Devanagari-based cluster or starting its cluster (not in emoji, Persian, Arabic or Latin clusters) | `zwj_between_consonants`, `zwnj_at_start`, `zwj_after_matra`, `double_joiner_after_virama`; not flagged: `emoji_family_zwj`, `persian_zwnj_word` |
| `mixed_script_in_cluster` | the cluster's base is from another script and carries a Devanagari mark, or a Devanagari base carries a foreign combining mark (another Indic block, or non-Indic such as `U+0301`; not a variation selector or a Vedic Extensions mark). Suppresses the other rules for that cluster (one issue, the root cause). | `latin_base_devanagari_matra`, `bengali_mark_on_devanagari`, `tamil_base_devanagari_virama`, `ka_combining_acute`, `ka_combining_enclosing_keycap` |
| `unexpected_code_point` | any code point in the "Unexpected" row of the table, including a tag character in a Devanagari-based cluster or starting its cluster | `replacement_char`, `private_use`, `private_use_legacy_font`, `tag_a_after_consonant`, `tag_language_tag` |
| `control_character` | any code point in the "Control (flagged)" row | `control_bell`, `bidi_control`, `bom_mid_text`, `nul` |

Where the table above is silent, the implementation generalises as follows (each has a case in the
table): a virama after a bindu, visarga or Vedic sign is `virama_without_consonant` (a virama needs a
consonant, or a consonant and its nukta, directly before it); a bindu or visarga on a digit, danda or
dead consonant is `stray_combining_mark`, and a Vedic sign on a dead consonant is valid; a nukta
directly after a virama is `nukta_on_non_consonant`; a second visarga is not flagged. For
`sign_before_matra`, `multiple_anusvara_like` and `double_matra` the cluster's code points are
counted since the current consonant started, wherever they sit.

Precedence: `mixed_script_in_cluster` is exclusive for its cluster (a cluster with both a foreign mark and
a tag reports the foreign mark only). `control_character` and
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
pub fn validate(text: &str) -> Result<Report, Error>;   // Err(InputTooLarge) above MAX_INPUT_BYTES (4 MiB)
pub fn clusters(text: &str) -> Vec<Cluster>;            // UAX #29 clusters with byte offsets
pub fn to_canonical_json(report: &Report) -> String;
pub fn score_ppm(penalty: u64, cluster_count: usize) -> u32;

pub struct Report      { spec: "glyphsift.report/0.2", script: "devanagari", code_points, clusters: Vec<Cluster>,
                         issues: Vec<Issue>, summary: Summary, lines: Vec<LineSummary>, score: Score }
pub struct Cluster     { index, text, start, end, code_points: Vec<"U+XXXX"> }
pub struct Issue       { kind: IssueKind, cluster: usize, code_point: Option<"U+XXXX"> }
pub struct Summary     { cluster_count, issue_count, flagged_clusters, by_kind: BTreeMap<IssueKind, usize> }
pub struct LineSummary { index, start, end, cluster_start, cluster_end, flagged_clusters, score_ppm }
pub struct Score       { ppm: u32, penalty: u64, weights: BTreeMap<IssueKind, u32> }
```

Report 0.2 adds `summary.by_kind`, `lines` and `score` to 0.1; nothing was removed or renamed.
`by_kind` lists only the rules that fired, in `IssueKind` declaration order. `weights` carries the
weight of all sixteen rules, so a consumer can recompute the score from the issues.

CLI: `glyphsift check <file|-> [--fail-under <ppm>]` prints the canonical report and exits 0, or 4
when the score is below the threshold (the report is still printed), 1 on an I/O or UTF-8 error or an
input over 4 MiB, 2 on a usage error. Python: `glyphsift.validate(text) -> str`,
`glyphsift.score_ppm(text) -> int` and `glyphsift.clusters(text) -> list[str]` (all three raise
`ValueError` over the limit). WASM: `validate(text) -> string`, `score_ppm(text) -> number`,
`report_spec()`, `clusters`, `clusters_json`, `issue_kinds` (all throw on over-limit input and never
trap). Scores are integers in parts per million, never floats, so the
canonical JSON stays bit-identical across runtimes for valid Unicode text.

## 6. Score and canonical JSON

### The score

A flagged cluster (one with at least one issue) costs the **largest** weight among the weights of
its issues, so two issues in one cluster count once. With `penalty` the sum of those costs over the
document, the document score in parts per million is

```
ppm = 1_000_000 - floor(penalty * 1000 / cluster_count)      saturating at 0
ppm = 1_000_000                                                for empty input
```

so one broken cluster out of four at weight 1000 scores 750_000. A line is the clusters from the one
after the previous line's terminator up to and including its own terminator cluster (LF, CRLF or a
bare CR; a CRLF cluster is two allowed controls and is never flagged); the same formula is applied
to the line's clusters alone and reported as `lines[i].score_ppm`. A final line without a
terminator is a line; a trailing terminator does not start another. `Report.score.ppm` divided by
10^6 is the 0 to 1 figure; **display it with four decimals by integer formatting, truncated and not
rounded** (`704762` is `0.7047`), as the CLI, the demo and the chart do.

### The weights

`crates/glyphsift-core/weights/devanagari.toml` holds one integer in `1..=1000` per rule, and every
line of the file carries a `# source:` comment saying why. The file is valid TOML and is read by a
strict parser (`Weights::parse`) that refuses a missing rule, a duplicate, an unknown name, a
non-integer, and a weight outside `1..=1000`; the crate compiles the file in with `include_str!`.
The groups follow how badly the cluster breaks rendering or reading (Unicode Standard chapter 12
where rendering is the reason):

| Weight | Rules |
| --- | --- |
| 1000 | `control_character`, `unexpected_code_point`, `mixed_script_in_cluster`, `dependent_vowel_without_base`, `stray_combining_mark` |
| 800 | `virama_without_consonant`, `double_matra`, `vowel_sign_on_independent_vowel` |
| 600 | `nukta_on_non_consonant`, `double_nukta`, `virama_after_matra` |
| 400 | `nukta_after_matra`, `sign_before_matra`, `multiple_anusvara_like`, `visarga_before_anusvara` |
| 200 | `zwj_zwnj_misplaced` |

The weights are an author's judgement, not a fit: they were fixed before the first benchmark run
(the SHA-256 of the file is logged before it) and are never tuned on benchmark output. Changing one
changes every score, so it is a `CHANGELOG.md` entry with its reason.

### Canonical JSON

`serde_json::to_string` (compact, no whitespace), struct fields in declaration order, every
collection a `Vec` in input order (`by_kind` and `weights` are `BTreeMap`s keyed by `IssueKind`, so
they follow declaration order), strings escaped exactly as JSON.stringify does (`"`, `\`,
`U+0000..U+001F`; `/` not escaped), no floating-point values anywhere. `serde_json` is built without
`preserve_order`. This is what makes the native, Python and WASM outputs byte-identical for valid Unicode text;
`scripts/determinism.sh` checks it on thirteen samples and the WASM safety script on 20,000 fuzz
inputs.

## 7. Known gaps

- Devanagari Extended cantillation marks (`U+A8E0..U+A8F1`) are still "unexpected"; Vedic text will
  need them classed as Vedic signs.
- `U+094E` and `U+094F` (prishthamatra e, aw) are matras here; their rendering order differs from
  other matras and may need a dedicated rule.
- Nukta on `र` to give `ऱ` (Marathi) and on `ळ` to give `ऴ` are valid and covered by the general
  nukta rule; no special-casing yet.
- Rules judge one cluster at a time. Document-level signals (legacy-font text decoded as Latin,
  repeated-cluster runs, a run of valid-looking but meaningless words) are not seen: such text
  scores clean.
- Scripts other than Devanagari are plain text: a Latin or Tamil word with no Devanagari mark is
  never flagged.
- Variation selectors (`U+FE00..U+FE0F`, `U+E0100..U+E01EF`) are not flagged on a Devanagari base:
  they change nothing visible there, and a Devanagari consonant followed by one scores clean.
- Invisible text outside Devanagari-based clusters is not looked for: a tag character after a Latin
  letter, or a joiner on a space's cluster, is not flagged.
- **Invisible and default-ignorable characters score clean (the invisible-text gap is not fully closed).**
  After a Devanagari base, each of these is accepted today and costs nothing; the table pins every one as
  a `known_gap_*` case in `crates/glyphsift-core/tests/cases/devanagari.toml`:
  - `U+200B` ZERO WIDTH SPACE, `U+2060` WORD JOINER, `U+00AD` SOFT HYPHEN and `U+2062` INVISIBLE TIMES. UAX #29
    puts each in a cluster of its own, so no per-cluster rule sees it next to the base.
  - In-cluster Extend characters whose General_Category is not Mn, Mc or Me: `U+1F3FB..U+1F3FF` (emoji
    modifiers, Sk) and `U+FF9E`, `U+FF9F` (halfwidth voiced and semi-voiced marks, Lm). They join the base's
    cluster, and the combining-mark rules look only at Mn, Mc and Me.
  Tag characters, bidi controls and foreign Mn/Mc/Me marks inside a Devanagari cluster are flagged (BUG-T2-S2-15);
  the list above is what is still not. Closing it needs a rule change, a new score weight and a new bench
  CSV, so it is deferred and the rule count stays 16.
- **Lone surrogates differ by runtime (valid Unicode text is identical everywhere).** A Rust `str` cannot hold a
  lone surrogate, so each binding handles it at its own boundary: Python raises `UnicodeEncodeError` before the
  validator runs; WASM and JavaScript replace it with `U+FFFD`, which is reported as `unexpected_code_point`; the
  CLI refuses invalid UTF-8 with exit code 1. The byte-identical guarantee is for valid Unicode text.
