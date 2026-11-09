//! Tests for the corruption generator (D3-03), written before `src/corrupt.rs`.
//! Run with `cargo test -p glyphsift-core --features corrupt` (the workspace `cargo test` enables
//! the feature through the CLI).

use std::collections::BTreeSet;
use std::path::Path;

use glyphsift_core::corrupt::{
    Corrupted, Family, SCHEDULE, SCHEDULE_PPM, Selection, Strength, corrupt, fnv1a64, p_label,
    parse_p_ppm, sites_json, splitmix64,
};
use glyphsift_core::{IssueKind, clusters, validate};

fn read(rel: &str) -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join(rel);
    std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
}

fn corpus() -> String {
    read("../../bench/corpus/clean.txt")
}

fn all_selections() -> Vec<Selection> {
    let mut v: Vec<Selection> = Family::ALL.iter().map(|&f| Selection::Family(f)).collect();
    v.push(Selection::Mixed);
    v
}

fn one(clean: &str, family: Family, seed: u64) -> Corrupted {
    corrupt(clean, Selection::Family(family), 1_000_000, seed)
}

fn is_matra(c: char) -> bool {
    matches!(c as u32, 0x093A | 0x093B | 0x093E..=0x094C | 0x094E | 0x094F | 0x0955..=0x0957 | 0x0962 | 0x0963)
}

// ---- the clean corpus -----------------------------------------------------------------------------

#[test]
fn clean_corpus_has_at_least_150_lines_each_validating_with_zero_issues() {
    let text = corpus();
    let lines: Vec<&str> = text.split_inclusive('\n').collect();
    assert!(lines.len() >= 150, "only {} lines", lines.len());
    assert!(text.ends_with('\n'), "the corpus ends with a newline");
    assert!(!text.contains('\r'), "LF line endings only");
    assert!(!text.starts_with('\u{FEFF}'), "no BOM");
    let mut devanagari_lines = 0;
    for (n, line) in lines.iter().enumerate() {
        assert!(line.trim().len() > 5, "line {} is empty or trivial", n + 1);
        let r = validate(line).unwrap();
        assert!(
            r.issues.is_empty(),
            "line {} has issues {:?}: {line}",
            n + 1,
            r.issues
        );
        if line.chars().any(|c| ('\u{0900}'..='\u{097F}').contains(&c)) {
            devanagari_lines += 1;
        }
    }
    assert_eq!(
        devanagari_lines,
        lines.len(),
        "every line is Devanagari text"
    );
    let whole = validate(&text).unwrap();
    assert!(whole.issues.is_empty());
    assert_eq!(whole.score.ppm, 1_000_000);
    assert!(
        whole.summary.cluster_count >= 5_000,
        "corpus is too small to chart"
    );
}

#[test]
fn clean_corpus_keeps_nuktas_decomposed_and_exercises_every_family() {
    let text = corpus();
    assert!(
        text.contains('\u{093C}'),
        "nukta words are needed for nukta_loss"
    );
    assert!(
        !text.chars().any(|c| ('\u{0958}'..='\u{095F}').contains(&c)),
        "precomposed nukta consonants are composition exclusions; keep the corpus decomposed"
    );
    for family in Family::ALL {
        let c = one(&text, family, 1);
        assert!(
            c.sites.len() >= 20,
            "{} found only {} eligible sites in the corpus",
            family.name(),
            c.sites.len()
        );
    }
}

// ---- p, the schedule and the arithmetic -------------------------------------------------------

#[test]
fn p_parses_as_a_decimal_in_parts_per_million() {
    assert_eq!(parse_p_ppm("0"), Ok(0));
    assert_eq!(parse_p_ppm("1"), Ok(1_000_000));
    assert_eq!(parse_p_ppm("0.05"), Ok(50_000));
    assert_eq!(parse_p_ppm("0.4"), Ok(400_000));
    assert_eq!(parse_p_ppm("0.000001"), Ok(1));
    assert_eq!(parse_p_ppm("0.123456"), Ok(123_456));
    assert_eq!(parse_p_ppm("1.000000"), Ok(1_000_000));
    for bad in [
        "",
        ".",
        ".5",
        "5.",
        "0.0000001",
        "1.000001",
        "1.5",
        "2",
        "-0.1",
        "+0.1",
        "0,1",
        "abc",
        "0.1x",
        " 0.1",
        "0.1 ",
        "1e-2",
        "NaN",
    ] {
        assert!(parse_p_ppm(bad).is_err(), "{bad:?} must be refused");
    }
}

#[test]
fn the_schedule_strings_and_ppm_values_agree() {
    assert_eq!(SCHEDULE.len(), SCHEDULE_PPM.len());
    for (s, ppm) in SCHEDULE.iter().zip(SCHEDULE_PPM) {
        assert_eq!(parse_p_ppm(s), Ok(ppm), "{s}");
        assert_eq!(&p_label(ppm), s);
    }
    assert_eq!(p_label(1_000_000), "1");
    assert_eq!(p_label(123_456), "0.123456");
    assert_eq!(p_label(1), "0.000001");
}

#[test]
fn the_hash_and_mixing_functions_match_their_published_vectors() {
    // FNV-1a 64: the reference vectors from the FNV authors' test suite.
    assert_eq!(fnv1a64(b""), 0xcbf2_9ce4_8422_2325);
    assert_eq!(fnv1a64(b"a"), 0xaf63_dc4c_8601_ec8c);
    assert_eq!(fnv1a64(b"foobar"), 0x8594_4171_f739_67e8);
    // SplitMix64 as a pure function of x: the first outputs of the reference generator seeded 0
    // are splitmix64(0), splitmix64(gamma), ... because the generator adds gamma before mixing.
    assert_eq!(splitmix64(0), 0xe220_a839_7b1d_cdaf);
    assert_eq!(splitmix64(0x9E37_79B9_7F4A_7C15), 0x6e78_9e6a_a1b9_65f4);
}

// ---- determinism and the coupling across p -----------------------------------------------------

#[test]
fn p_zero_is_the_identity_for_every_family_and_seed() {
    let text = corpus();
    for sel in all_selections() {
        for seed in [1, 2, 3] {
            let c = corrupt(&text, sel, 0, seed);
            assert_eq!(c.text, text, "{} seed {seed}", sel.name());
            assert!(c.sites.is_empty());
        }
    }
}

#[test]
fn the_same_seed_gives_byte_identical_output_and_another_seed_does_not() {
    let text = corpus();
    for sel in all_selections() {
        let a = corrupt(&text, sel, 200_000, 7);
        let b = corrupt(&text, sel, 200_000, 7);
        assert_eq!(a, b, "{}", sel.name());
        let c = corrupt(&text, sel, 200_000, 8);
        assert_ne!(
            a.text,
            c.text,
            "{}: seeds 7 and 8 gave the same text",
            sel.name()
        );
    }
}

#[test]
fn site_sets_are_nested_across_the_schedule() {
    let text = corpus();
    for sel in all_selections() {
        for seed in [1, 2, 3] {
            let mut previous: BTreeSet<usize> = BTreeSet::new();
            for ppm in SCHEDULE_PPM {
                let c = corrupt(&text, sel, ppm, seed);
                let now: BTreeSet<usize> = c.sites.iter().map(|s| s.source).collect();
                assert!(
                    previous.is_subset(&now),
                    "{} seed {seed} p_ppm {ppm}: sites are not a superset of the previous step",
                    sel.name()
                );
                previous = now;
            }
            assert!(
                !previous.is_empty(),
                "{} seed {seed}: no sites at p=0.4",
                sel.name()
            );
        }
    }
}

#[test]
fn a_site_is_corrupted_the_same_way_at_every_p_where_it_is_selected() {
    // The replacement stream does not depend on p: a site chosen at p=0.1 is replaced by exactly
    // the same text at p=0.4.
    let text = corpus();
    for sel in all_selections() {
        let lo = corrupt(&text, sel, 100_000, 2);
        let hi = corrupt(&text, sel, 400_000, 2);
        assert!(lo.sites.len() < hi.sites.len(), "{}", sel.name());
        for s in &lo.sites {
            let twin = hi
                .sites
                .iter()
                .find(|h| h.source == s.source)
                .unwrap_or_else(|| panic!("{}: site {} vanished at p=0.4", sel.name(), s.source));
            assert_eq!(
                twin.replacement,
                s.replacement,
                "{} site {}",
                sel.name(),
                s.source
            );
            assert_eq!((twin.family, &twin.kinds), (s.family, &s.kinds));
        }
    }
}

#[test]
fn mixed_assigns_each_site_to_the_family_given_by_splitmix_of_seed_xor_index() {
    let text = corpus();
    let seed = 5u64;
    let c = corrupt(&text, Selection::Mixed, 400_000, seed);
    assert!(c.sites.len() > 100);
    let mut families = BTreeSet::new();
    for s in &c.sites {
        let want =
            Family::ALL[(splitmix64(seed ^ s.source as u64) % Family::ALL.len() as u64) as usize];
        assert_eq!(s.family, want, "site {}", s.source);
        families.insert(s.family);
    }
    assert!(
        families.len() >= 15,
        "mixed used only {} families",
        families.len()
    );
    // Sites are in input order and their output clusters never go backwards.
    assert!(c.sites.windows(2).all(|w| w[0].source < w[1].source));
    assert!(c.sites.windows(2).all(|w| w[0].cluster <= w[1].cluster));
}

// ---- the family table in the docs -------------------------------------------------------------

#[test]
fn the_docs_table_and_the_code_agree_on_families_rules_and_strength() {
    let doc = read("../../docs/corruption-generator.md");
    let mut rows: Vec<(String, String)> = Vec::new();
    for line in doc.lines() {
        if let Some(rest) = line.strip_prefix("| `") {
            let cols: Vec<&str> = line.split('|').collect();
            if cols.len() >= 6 {
                let name = rest.split('`').next().unwrap().to_owned();
                rows.push((name, cols[4].to_owned()));
            }
        }
    }
    let doc_names: Vec<&str> = rows.iter().map(|r| r.0.as_str()).collect();
    let code_names: Vec<&str> = Family::ALL.iter().map(|f| f.name()).collect();
    assert_eq!(doc_names, code_names, "family list and order");
    for (name, rules_col) in &rows {
        let family = Family::from_name(name).unwrap();
        let in_doc: BTreeSet<IssueKind> = rules_col
            .split('`')
            .skip(1)
            .step_by(2)
            .filter_map(IssueKind::from_name)
            .collect();
        let in_code: BTreeSet<IssueKind> = family.triggers().iter().copied().collect();
        assert_eq!(in_doc, in_code, "{name}: rules column");
        let none_directly = rules_col.contains("none directly");
        assert_eq!(
            none_directly,
            family.strength() == Strength::NoneDirectly,
            "{name}: strength"
        );
    }
}

#[test]
fn sidecar_kinds_come_from_the_family_table() {
    let text = corpus();
    for sel in all_selections() {
        let c = corrupt(&text, sel, 400_000, 1);
        for s in &c.sites {
            let allowed: BTreeSet<IssueKind> = s.family.triggers().iter().copied().collect();
            for k in &s.kinds {
                assert!(
                    allowed.contains(k),
                    "{}: site {} declares {k} which {} does not list",
                    sel.name(),
                    s.source,
                    s.family.name()
                );
            }
            if s.family.strength() == Strength::NoneDirectly {
                assert!(s.kinds.is_empty(), "{}", s.family.name());
            }
        }
    }
}

#[test]
fn sites_name_a_valid_cluster_of_the_corrupted_output() {
    let text = corpus();
    for sel in all_selections() {
        let c = corrupt(&text, sel, 400_000, 3);
        let n = clusters(&c.text).len();
        for s in &c.sites {
            assert!(
                s.cluster < n,
                "{}: cluster {} of {n}",
                sel.name(),
                s.cluster
            );
        }
    }
}

#[test]
fn recall_at_p_0_05_is_at_least_0_9_for_families_that_declare_a_rule() {
    let text = corpus();
    for family in Family::ALL {
        let (mut declared, mut hit) = (0usize, 0usize);
        for seed in [1, 2, 3] {
            let c = corrupt(&text, Selection::Family(family), 50_000, seed);
            let report = validate(&c.text).unwrap();
            for s in c.sites.iter().filter(|s| !s.kinds.is_empty()) {
                declared += 1;
                if report
                    .issues
                    .iter()
                    .any(|i| i.cluster == s.cluster && s.kinds.contains(&i.kind))
                {
                    hit += 1;
                }
            }
        }
        if family.triggers().is_empty() {
            assert_eq!(declared, 0, "{}", family.name());
        } else {
            assert!(declared > 0, "{}: no site declared a rule", family.name());
            assert!(
                hit * 10 >= declared * 9,
                "{}: recall {hit}/{declared} is below 0.9",
                family.name()
            );
        }
    }
}

// ---- what each family does to a tiny input -----------------------------------------------------

#[test]
fn matra_detach_inserts_a_space_before_the_matra() {
    let c = one("कि\n", Family::MatraDetach, 1);
    assert_eq!(c.text, "क ि\n");
    assert_eq!(c.sites.len(), 1);
    assert_eq!(c.sites[0].source, 0);
    assert_eq!(c.sites[0].cluster, 1);
    assert_eq!(c.sites[0].kinds, [IssueKind::DependentVowelWithoutBase]);
    let r = validate(&c.text).unwrap();
    assert_eq!(r.issues.len(), 1);
    assert_eq!(r.issues[0].cluster, 1);
}

#[test]
fn matra_drop_matra_swap_and_matra_double_edit_the_matra() {
    assert_eq!(one("का", Family::MatraDrop, 1).text, "क");
    let swap = one("का", Family::MatraSwap, 1).text;
    let chars: Vec<char> = swap.chars().collect();
    assert_eq!(chars.len(), 2);
    assert_eq!(chars[0], 'क');
    assert!(
        is_matra(chars[1]) && chars[1] != 'ा',
        "swapped to {:?}",
        chars[1]
    );
    let dbl = one("का", Family::MatraDouble, 1);
    let chars: Vec<char> = dbl.text.chars().collect();
    assert_eq!(chars.len(), 3);
    assert_eq!(&chars[..2], ['क', 'ा']);
    assert!(is_matra(chars[2]));
    assert_eq!(dbl.sites[0].kinds, [IssueKind::DoubleMatra]);
    assert_eq!(
        validate(&dbl.text).unwrap().issues[0].kind,
        IssueKind::DoubleMatra
    );
}

#[test]
fn nukta_loss_and_nukta_spurious() {
    let lost = one("ज\u{093C}", Family::NuktaLoss, 1);
    assert_eq!(lost.text, "ज");
    assert!(lost.sites[0].kinds.is_empty());
    // A consonant with a matra: the nukta goes right after the consonant (valid) or after the
    // matra (nukta_after_matra).
    let spur = one("कि", Family::NuktaSpurious, 1);
    assert!(
        ["क\u{093C}ि", "कि\u{093C}"].contains(&spur.text.as_str()),
        "{:?}",
        spur.text
    );
    assert_eq!(spur.sites[0].kinds.is_empty(), spur.text == "क\u{093C}ि");
    // A vowel and a digit can only take the nukta as an error.
    let v = one("अ", Family::NuktaSpurious, 1);
    assert_eq!(v.text, "अ\u{093C}");
    assert_eq!(v.sites[0].kinds, [IssueKind::NuktaOnNonConsonant]);
    assert_eq!(one("१", Family::NuktaSpurious, 1).text, "१\u{093C}");
}

#[test]
fn virama_delete_and_virama_insert() {
    assert_eq!(one("क्ष", Family::ViramaDelete, 1).text, "कष");
    let after_matra = one("कि", Family::ViramaInsert, 1);
    assert_eq!(after_matra.text, "कि्");
    assert_eq!(after_matra.sites[0].kinds, [IssueKind::ViramaAfterMatra]);
    let on_vowel = one("अ", Family::ViramaInsert, 1);
    assert_eq!(on_vowel.text, "अ्");
    assert_eq!(on_vowel.sites[0].kinds, [IssueKind::ViramaWithoutConsonant]);
    let twice = one("क", Family::ViramaInsert, 1);
    assert_eq!(twice.text, "क््");
    assert_eq!(twice.sites[0].kinds, [IssueKind::ViramaWithoutConsonant]);
}

#[test]
fn bindu_swap_and_sign_order() {
    for seed in 1..=20 {
        let c = one("कं", Family::BinduSwap, seed);
        let both = c.text == "कं\u{0901}";
        assert!(c.text == "कँ" || both, "{:?}", c.text);
        assert_eq!(c.sites[0].kinds.is_empty(), !both);
    }
    let c = one("कां", Family::SignOrder, 1);
    assert_eq!(c.text, "कंा");
    assert_eq!(c.sites[0].kinds, [IssueKind::SignBeforeMatra]);
    let swapped = one("कंः", Family::SignOrder, 1);
    assert_eq!(swapped.text, "कःं");
    assert_eq!(swapped.sites[0].kinds, [IssueKind::VisargaBeforeAnusvara]);
}

#[test]
fn reph_misplace_ocr_confusion_digit_danda() {
    for seed in 1..=10 {
        let t = one("र्म", Family::RephMisplace, seed).text;
        assert!(t == "म्र" || t == "रम", "{t:?}");
    }
    assert_eq!(one("बघभटऱडय", Family::OcrConfusion, 1).text, "वधमढरङथ");
    assert_eq!(one("॥", Family::DigitDanda, 1).text, "।।");
    let d = one("३", Family::DigitDanda, 1).text;
    assert!(["3", "।", "|"].contains(&d.as_str()), "{d:?}");
    let danda = one("।", Family::DigitDanda, 1).text;
    assert!(["|", "1"].contains(&danda.as_str()), "{danda:?}");
}

#[test]
fn word_boundary_deletes_a_space_or_detaches_a_matra_or_virama() {
    let del = one("क ख", Family::WordBoundary, 1);
    assert_eq!(del.text, "कख");
    assert!(del.sites[0].kinds.is_empty());
    let matra = one("कि", Family::WordBoundary, 1);
    assert_eq!(matra.text, "क ि");
    assert_eq!(matra.sites[0].kinds, [IssueKind::DependentVowelWithoutBase]);
    let virama = one("क्ष", Family::WordBoundary, 1);
    assert_eq!(virama.text, "क ्ष");
    assert_eq!(virama.sites[0].kinds, [IssueKind::ViramaWithoutConsonant]);
    assert!(
        validate(&virama.text)
            .unwrap()
            .issues
            .iter()
            .any(|i| i.kind == IssueKind::ViramaWithoutConsonant)
    );
}

#[test]
fn joiner_inject_never_follows_a_virama_and_always_trips_the_rule() {
    let c = one("कख", Family::JoinerInject, 1);
    assert_eq!(c.sites.len(), 2, "boundaries before both clusters");
    let r = validate(&c.text).unwrap();
    assert_eq!(r.issues.len(), 2);
    assert!(
        r.issues
            .iter()
            .all(|i| i.kind == IssueKind::ZwjZwnjMisplaced)
    );
    for s in &c.sites {
        assert!(r.issues.iter().any(|i| i.cluster == s.cluster));
    }
    // After "क्" + ZWNJ the boundary is after a virama: only the boundary before the first cluster.
    let blocked = one("क्\u{200C}ख", Family::JoinerInject, 1);
    assert_eq!(blocked.sites.len(), 1);
    assert_eq!(blocked.sites[0].source, 0);
}

#[test]
fn control_leak_skips_the_start_of_the_text_and_always_trips_the_rule() {
    let c = one("कख", Family::ControlLeak, 1);
    assert_eq!(c.sites.len(), 1, "no control is inserted at offset 0");
    assert_eq!(c.sites[0].source, 1);
    assert_eq!(c.sites[0].cluster, 1);
    assert_eq!(c.sites[0].kinds, [IssueKind::ControlCharacter]);
    let leaked: Vec<char> = c.text.chars().collect();
    assert_eq!(leaked.len(), 3);
    assert!(['\u{FEFF}', '\u{200E}', '\u{202E}', '\u{0007}'].contains(&leaked[1]));
    let r = validate(&c.text).unwrap();
    assert_eq!(r.issues.len(), 1);
    assert_eq!(r.issues[0].cluster, 1);
}

#[test]
fn legacy_font_moves_the_short_i_splits_reph_and_flattens_nukta() {
    let i = one("कि", Family::LegacyFont, 1);
    assert_eq!(i.text, "िक");
    assert_eq!(i.sites[0].kinds, [IssueKind::DependentVowelWithoutBase]);
    assert_eq!(
        validate(&i.text).unwrap().issues[0].kind,
        IssueKind::DependentVowelWithoutBase
    );
    let reph = one("र्म", Family::LegacyFont, 1);
    assert_eq!(reph.text, "म\u{F0D0}");
    assert_eq!(reph.sites[0].kinds, [IssueKind::UnexpectedCodePoint]);
    assert_eq!(reph.sites[0].cluster, 1);
    let nukta = one("ज\u{093C}", Family::LegacyFont, 1);
    assert_eq!(nukta.text, "ज");
    assert!(nukta.sites[0].kinds.is_empty());
    // A short-i matra in the middle of a word is not eligible: it would just attach to the
    // previous consonant, which no rule can see.
    let mid = one("किकि", Family::LegacyFont, 1);
    assert_eq!(mid.sites.len(), 1);
    assert_eq!(mid.sites[0].source, 0);
}

#[test]
fn mixed_script_puts_a_latin_base_or_another_indic_matra_on_the_cluster() {
    for seed in 1..=10 {
        let c = one("कि", Family::MixedScript, seed);
        let chars: Vec<char> = c.text.chars().collect();
        assert_eq!(chars.len(), 2);
        let latin_base = matches!(chars[0], 'A' | 'e' | 'o') && chars[1] == 'ि';
        let other_matra = chars[0] == 'क' && matches!(chars[1] as u32, 0x09BF | 0x0A3F);
        assert!(latin_base || other_matra, "{:?}", c.text);
        assert_eq!(c.sites[0].kinds, [IssueKind::MixedScriptInCluster]);
        let r = validate(&c.text).unwrap();
        assert_eq!(r.issues.len(), 1);
        assert_eq!(r.issues[0].kind, IssueKind::MixedScriptInCluster);
    }
}

#[test]
fn random_substitution_replaces_one_devanagari_code_point_with_another() {
    for seed in 1..=10 {
        let c = one("क", Family::RandomSubstitution, seed);
        let chars: Vec<char> = c.text.chars().collect();
        assert_eq!(chars.len(), 1);
        assert!(('\u{0900}'..='\u{097F}').contains(&chars[0]) && chars[0] != 'क');
        assert!(c.sites[0].kinds.is_empty());
    }
}

// ---- no panic ----------------------------------------------------------------------------------

#[test]
fn no_family_panics_on_hostile_input_and_sites_stay_in_range() {
    // Strings from xorshift64* over U+0000..U+097F plus joiners, PUA and a few astral code points.
    let mut state = 0x1234_5678_9ABC_DEF1u64;
    let mut next = || {
        state ^= state >> 12;
        state ^= state << 25;
        state ^= state >> 27;
        state.wrapping_mul(0x2545_F491_4F6C_DD1D)
    };
    for _ in 0..400 {
        let len = (next() % 30) as usize;
        let text: String = (0..len)
            .map(|_| match next() % 40 {
                0 => '\u{200D}',
                1 => '\u{200C}',
                2 => '\u{F0D0}',
                3 => '\u{1F64F}',
                4 => '\u{FEFF}',
                _ => char::from_u32(0x900 + (next() % 0x80) as u32).unwrap(),
            })
            .collect();
        for sel in all_selections() {
            for ppm in [1_000_000, 500_000] {
                let c = corrupt(&text, sel, ppm, 9);
                let n = clusters(&c.text).len();
                assert!(c.sites.iter().all(|s| s.cluster < n.max(1)));
            }
        }
    }
    for sel in all_selections() {
        assert_eq!(corrupt("", sel, 1_000_000, 1).text, "");
    }
}

// ---- the sidecar -------------------------------------------------------------------------------

#[test]
fn the_sidecar_is_compact_json_in_a_fixed_field_order() {
    let c = one("कि\n", Family::MatraDetach, 4);
    let json = sites_json(Selection::Family(Family::MatraDetach), 4, 1_000_000, &c);
    assert_eq!(
        json,
        "{\"family\":\"matra_detach\",\"seed\":4,\"p_ppm\":1000000,\"sites\":[{\"source\":0,\
         \"cluster\":1,\"family\":\"matra_detach\",\"kinds\":[\"dependent_vowel_without_base\"]}]}"
    );
    let none = sites_json(
        Selection::Mixed,
        1,
        0,
        &corrupt("कि", Selection::Mixed, 0, 1),
    );
    assert_eq!(
        none,
        "{\"family\":\"mixed\",\"seed\":1,\"p_ppm\":0,\"sites\":[]}"
    );
}
