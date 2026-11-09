//! Tests for the document and line score (D3-02), written before `score.rs` and `Report` 0.2.
//!
//! Score: `penalty` = sum over flagged clusters of the largest weight among that cluster's issues;
//! `ppm = 1_000_000 - floor(penalty * 1000 / cluster_count)`, saturating; empty input scores
//! `1_000_000`. The same formula applies per line. Weights live in `weights/devanagari.toml`.

use glyphsift_core::{
    IssueKind, MAX_WEIGHT, REPORT_SPEC, Weights, WeightsError, score_ppm, to_canonical_json,
    validate,
};

const WEIGHTS_FILE: &str = include_str!("../weights/devanagari.toml");

/// The table from the sprint spec, as `(kind, weight)`.
fn spec_weights() -> Vec<(IssueKind, u32)> {
    use IssueKind::*;
    vec![
        (ControlCharacter, 1000),
        (UnexpectedCodePoint, 1000),
        (MixedScriptInCluster, 1000),
        (DependentVowelWithoutBase, 1000),
        (StrayCombiningMark, 1000),
        (ViramaWithoutConsonant, 800),
        (DoubleMatra, 800),
        (VowelSignOnIndependentVowel, 800),
        (NuktaOnNonConsonant, 600),
        (DoubleNukta, 600),
        (ViramaAfterMatra, 600),
        (NuktaAfterMatra, 400),
        (SignBeforeMatra, 400),
        (MultipleAnusvaraLike, 400),
        (VisargaBeforeAnusvara, 400),
        (ZwjZwnjMisplaced, 200),
    ]
}

// ---- the weights file --------------------------------------------------------------------------

#[test]
fn builtin_weights_match_the_sprint_spec() {
    let weights = Weights::builtin();
    let spec = spec_weights();
    assert_eq!(spec.len(), 16);
    for (kind, want) in spec {
        assert_eq!(weights.get(kind), want, "{kind}");
    }
}

#[test]
fn every_line_of_the_weights_file_carries_a_source_comment() {
    let mut weight_lines = 0;
    for (n, line) in WEIGHTS_FILE.lines().enumerate() {
        assert!(
            !line.trim().is_empty(),
            "line {}: blank lines are not allowed",
            n + 1
        );
        assert!(
            line.contains("# source:"),
            "line {} has no '# source:' comment: {line}",
            n + 1
        );
        if !line.trim_start().starts_with('#') {
            weight_lines += 1;
        }
    }
    assert_eq!(weight_lines, 16, "one weight line per IssueKind");
}

#[test]
fn the_weights_file_is_valid_toml_and_agrees_with_the_parser() {
    let table: toml::Table = toml::from_str(WEIGHTS_FILE).expect("valid TOML");
    assert_eq!(table.len(), 16);
    let weights = Weights::builtin();
    for kind in IssueKind::ALL {
        let v = table[kind.name()].as_integer().expect("integer weight");
        assert!((1..=i64::from(MAX_WEIGHT)).contains(&v), "{kind}: {v}");
        assert_eq!(i64::from(weights.get(kind)), v, "{kind}");
    }
}

fn full_file_with(kind: &str, replacement: Option<&str>) -> String {
    // The real file with one line replaced (or removed when `replacement` is None).
    let mut out = String::new();
    for line in WEIGHTS_FILE.lines() {
        if line.starts_with(&format!("{kind} ")) || line.starts_with(&format!("{kind}=")) {
            if let Some(r) = replacement {
                out.push_str(r);
                out.push('\n');
            }
        } else {
            out.push_str(line);
            out.push('\n');
        }
    }
    out
}

#[test]
fn a_file_missing_a_kind_is_refused() {
    let src = full_file_with("double_matra", None);
    assert_eq!(
        Weights::parse(&src),
        Err(WeightsError::Missing(IssueKind::DoubleMatra))
    );
}

#[test]
fn weights_outside_1_to_1000_are_refused() {
    for bad in ["0", "1001", "99999", "4294967296"] {
        let src = full_file_with(
            "double_matra",
            Some(&format!("double_matra = {bad} # source: test")),
        );
        assert!(
            matches!(Weights::parse(&src), Err(WeightsError::OutOfRange { .. })),
            "weight {bad} must be refused"
        );
    }
    // The boundaries themselves are fine.
    for ok in ["1", "1000"] {
        let src = full_file_with(
            "double_matra",
            Some(&format!("double_matra = {ok} # source: test")),
        );
        assert!(Weights::parse(&src).is_ok(), "weight {ok} must be accepted");
    }
}

#[test]
fn malformed_unknown_and_duplicate_lines_are_refused() {
    let unknown = format!("{WEIGHTS_FILE}not_a_rule = 5 # source: test\n");
    assert!(matches!(
        Weights::parse(&unknown),
        Err(WeightsError::UnknownKind { .. })
    ));
    let duplicate = format!("{WEIGHTS_FILE}double_matra = 5 # source: test\n");
    assert!(matches!(
        Weights::parse(&duplicate),
        Err(WeightsError::Duplicate { .. })
    ));
    for bad in [
        "double_matra 800",
        "double_matra = eight",
        "double_matra = 8.5",
        "double_matra = -3",
        "double_matra = 8_00",
        "= 800",
    ] {
        let src = full_file_with("double_matra", Some(&format!("{bad} # source: test")));
        assert!(
            matches!(Weights::parse(&src), Err(WeightsError::Syntax { .. })),
            "{bad:?} must be a syntax error"
        );
    }
}

// ---- the formula ---------------------------------------------------------------------------------

#[test]
fn score_ppm_follows_the_formula() {
    assert_eq!(score_ppm(0, 0), 1_000_000, "empty input");
    assert_eq!(score_ppm(0, 10), 1_000_000);
    assert_eq!(score_ppm(1000, 4), 750_000);
    assert_eq!(score_ppm(800, 1), 200_000);
    assert_eq!(score_ppm(200, 7), 971_429, "floor(200 * 1000 / 7) = 28_571");
    assert_eq!(score_ppm(1000, 1), 0);
    assert_eq!(score_ppm(5000, 1), 0, "saturates at zero");
    assert_eq!(score_ppm(u64::MAX, 1), 0, "no overflow");
}

// ---- reports -----------------------------------------------------------------------------------

#[test]
fn empty_input_scores_one_million_with_no_lines() {
    let r = validate("").unwrap();
    assert_eq!(r.spec, REPORT_SPEC);
    assert_eq!(r.spec, "glyphsift.report/0.2");
    assert_eq!(r.score.ppm, 1_000_000);
    assert_eq!(r.score.penalty, 0);
    assert!(r.lines.is_empty());
    assert!(r.summary.by_kind.is_empty());
}

#[test]
fn one_broken_cluster_of_four_scores_750_000() {
    // Three consonants and U+FFFD: four clusters, one unexpected_code_point (weight 1000).
    let r = validate("कखग\u{FFFD}").unwrap();
    assert_eq!(r.summary.cluster_count, 4);
    assert_eq!(r.summary.flagged_clusters, 1);
    assert_eq!(r.score.penalty, 1000);
    assert_eq!(r.score.ppm, 750_000);
}

#[test]
fn two_issues_in_one_cluster_count_once_at_the_larger_weight() {
    // "काा्": double_matra (800) and virama_after_matra (600) in one cluster, then three clean ones.
    let r = validate("काा्कखग").unwrap();
    assert_eq!(r.summary.cluster_count, 4);
    assert_eq!(r.summary.issue_count, 2);
    assert_eq!(r.summary.flagged_clusters, 1);
    assert_eq!(r.score.penalty, 800, "max(800, 600), not 1400");
    assert_eq!(r.score.ppm, 800_000);
}

#[test]
fn penalties_add_across_flagged_clusters() {
    // virama_after_matra (600) in one cluster, zwj_zwnj_misplaced (200) in another, 8 clusters.
    let r = validate("कि्क\u{200D}खगघङचछ").unwrap();
    assert_eq!(r.summary.cluster_count, 8);
    assert_eq!(r.summary.flagged_clusters, 2);
    assert_eq!(r.score.penalty, 800);
    assert_eq!(r.score.ppm, 900_000);
}

#[test]
fn the_report_carries_the_weights_it_used() {
    let r = validate("क").unwrap();
    assert_eq!(r.score.weights.len(), 16);
    for kind in IssueKind::ALL {
        assert_eq!(r.score.weights[&kind], Weights::builtin().get(kind));
    }
}

#[test]
fn by_kind_counts_every_issue_in_declaration_order() {
    // U+FFFD is unexpected_code_point; the lone matra is dependent_vowel_without_base (declared
    // first); the lone ZWNJ is zwj_zwnj_misplaced; the second matra of "काा" is double_matra.
    let r = validate("\u{FFFD} ि\u{200C}काा\u{FFFD}").unwrap();
    let json = to_canonical_json(&r);
    let start = json.find("\"by_kind\":").expect("by_kind present");
    let rest = &json[start..];
    let end = rest.find('}').unwrap();
    assert_eq!(
        &rest[..=end],
        "\"by_kind\":{\"dependent_vowel_without_base\":1,\"double_matra\":1,\
         \"zwj_zwnj_misplaced\":1,\"unexpected_code_point\":2}"
    );
    let total: usize = r.summary.by_kind.values().sum();
    assert_eq!(total, r.summary.issue_count);
}

#[test]
fn lines_split_after_lf_crlf_and_bare_cr_and_a_crlf_cluster_is_never_flagged() {
    // line 0: "कख\n"; line 1: "क\u{FFFD}\r\n" (one flagged cluster); line 2: "गघ" (no terminator).
    let text = "कख\nक\u{FFFD}\r\nगघ";
    let r = validate(text).unwrap();
    assert_eq!(r.summary.cluster_count, 8);
    assert_eq!(r.lines.len(), 3);

    let l0 = &r.lines[0];
    assert_eq!((l0.index, l0.start, l0.end), (0, 0, 7));
    assert_eq!((l0.cluster_start, l0.cluster_end), (0, 3));
    assert_eq!((l0.flagged_clusters, l0.score_ppm), (0, 1_000_000));

    let l1 = &r.lines[1];
    assert_eq!((l1.index, l1.start, l1.end), (1, 7, 15));
    assert_eq!((l1.cluster_start, l1.cluster_end), (3, 6));
    assert_eq!(l1.flagged_clusters, 1);
    assert_eq!(l1.score_ppm, 666_667, "1_000_000 - floor(1000 * 1000 / 3)");
    assert_eq!(r.clusters[5].text, "\r\n", "CRLF is one cluster");
    assert!(
        r.issues.iter().all(|i| i.cluster != 5),
        "the CRLF cluster is never flagged"
    );

    let l2 = &r.lines[2];
    assert_eq!((l2.index, l2.start, l2.end), (2, 15, 21));
    assert_eq!((l2.cluster_start, l2.cluster_end), (6, 8));
    assert_eq!((l2.flagged_clusters, l2.score_ppm), (0, 1_000_000));

    assert_eq!(r.score.penalty, 1000);
    assert_eq!(r.score.ppm, 875_000);

    let cr = validate("क\rख").unwrap();
    assert_eq!(cr.lines.len(), 2, "a bare CR ends a line");
    assert_eq!(cr.lines[0].end, 4);
}

#[test]
fn trailing_terminators_do_not_start_empty_lines() {
    assert_eq!(validate("क\n").unwrap().lines.len(), 1);
    let blank = validate("\n").unwrap();
    assert_eq!(blank.lines.len(), 1);
    assert_eq!(blank.lines[0].score_ppm, 1_000_000);
    assert_eq!(validate("क\n\n").unwrap().lines.len(), 2);
}

#[test]
fn lines_partition_the_clusters_and_the_bytes() {
    let text = "नमस्ते\nि दुनिया\r\n\nकाा्\n";
    let r = validate(text).unwrap();
    let mut next_cluster = 0;
    let mut next_byte = 0;
    let mut flagged = 0;
    for (i, line) in r.lines.iter().enumerate() {
        assert_eq!(line.index, i);
        assert_eq!(line.cluster_start, next_cluster);
        assert_eq!(line.start, next_byte);
        assert!(line.cluster_end > line.cluster_start, "no empty lines");
        next_cluster = line.cluster_end;
        next_byte = line.end;
        flagged += line.flagged_clusters;
    }
    assert_eq!(next_cluster, r.summary.cluster_count);
    assert_eq!(next_byte, text.len());
    assert_eq!(flagged, r.summary.flagged_clusters);
}

#[test]
fn the_score_is_deterministic_and_round_trips_through_json() {
    let text = "ोम काा ं नमस्ते िदुनिया";
    let a = to_canonical_json(&validate(text).unwrap());
    let b = to_canonical_json(&validate(text).unwrap());
    assert_eq!(a, b);
    let back: glyphsift_core::Report = serde_json::from_str(&a).unwrap();
    assert_eq!(to_canonical_json(&back), a);
}

// ---- determinism hygiene ---------------------------------------------------------------------

#[test]
fn core_sources_use_no_floats_and_no_hash_collections() {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let forbidden = ["f32", "f64", "HashMap", "HashSet"];
    let mut checked = 0;
    for entry in std::fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.extension().is_some_and(|e| e == "rs") {
            let text = std::fs::read_to_string(&path).unwrap();
            for token in forbidden {
                assert!(!text.contains(token), "{} mentions {token}", path.display());
            }
            checked += 1;
        }
    }
    assert!(checked >= 5, "expected to scan the core sources");
}
