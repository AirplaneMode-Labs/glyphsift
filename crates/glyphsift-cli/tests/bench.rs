//! `glyphsift bench` (D3-04), written before the subcommand.
//!
//! The benchmark corrupts `bench/corpus/clean.txt` at the schedule p in {0, 0.01, 0.02, 0.05, 0.1,
//! 0.2, 0.4} for every family and `mixed`, seeds 1 to 3, scores each result and checks:
//!   (a) the mixed-family mean score falls STRICTLY at every step from p=0 to p=0.4;
//!   (b) mixed is non-increasing in p for each seed;
//!   (c) every triggering family is non-increasing in p for each seed;
//!   (d) score_ppm is 1_000_000 at p=0 for every row.
//! It exits 1 on any violation. These tests re-derive the verdict from the CSV independently.

mod common;

use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use common::{run, scratch};
use glyphsift_core::corrupt::{Family, SCHEDULE, Strength};

const HEADER: &str = "family,p,seed,cluster_count,flagged_clusters,score_ppm,recall_ppm";

fn root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

struct Outputs {
    csv: String,
    svg: String,
}

fn bench_into(dir: &str) -> (common::Run, Outputs) {
    let d = scratch(dir);
    let (csv, svg) = (d.join("out.csv"), d.join("out.svg"));
    let corpus = root().join("bench/corpus/clean.txt");
    let r = run(
        &[
            "bench",
            "--corpus",
            corpus.to_str().unwrap(),
            "--seeds",
            "1,2,3",
            "--csv",
            csv.to_str().unwrap(),
            "--svg",
            svg.to_str().unwrap(),
        ],
        b"",
    );
    let out = Outputs {
        csv: std::fs::read_to_string(&csv).unwrap_or_default(),
        svg: std::fs::read_to_string(&svg).unwrap_or_default(),
    };
    (r, out)
}

/// One real run, shared by the tests that only read its outputs.
fn first_run() -> &'static (i32, String, Outputs) {
    static RUN: OnceLock<(i32, String, Outputs)> = OnceLock::new();
    RUN.get_or_init(|| {
        let (r, out) = bench_into("bench-first");
        (r.code, r.out(), out)
    })
}

struct Row {
    family: String,
    p: String,
    seed: u64,
    cluster_count: u64,
    flagged: u64,
    score: u64,
    recall: Option<u64>,
}

fn parse(csv: &str) -> Vec<Row> {
    let mut lines = csv.lines();
    assert_eq!(lines.next(), Some(HEADER));
    lines
        .map(|l| {
            let f: Vec<&str> = l.split(',').collect();
            assert_eq!(f.len(), 7, "{l}");
            Row {
                family: f[0].to_owned(),
                p: f[1].to_owned(),
                seed: f[2].parse().unwrap(),
                cluster_count: f[3].parse().unwrap(),
                flagged: f[4].parse().unwrap(),
                score: f[5].parse().unwrap(),
                recall: if f[6].is_empty() {
                    None
                } else {
                    Some(f[6].parse().unwrap())
                },
            }
        })
        .collect()
}

fn series(rows: &[Row], family: &str, seed: u64) -> Vec<u64> {
    SCHEDULE
        .iter()
        .map(|p| {
            rows.iter()
                .find(|r| r.family == family && r.seed == seed && r.p == *p)
                .unwrap_or_else(|| panic!("no row for {family} p={p} seed {seed}"))
                .score
        })
        .collect()
}

fn names() -> Vec<String> {
    let mut v: Vec<String> = Family::ALL.iter().map(|f| f.name().to_owned()).collect();
    v.push("mixed".to_owned());
    v
}

// ---- the real run -------------------------------------------------------------------------------

#[test]
fn bench_exits_0_and_writes_a_complete_csv() {
    let (code, stdout, out) = first_run();
    assert_eq!(*code, 0, "stdout:\n{stdout}");
    assert!(stdout.contains("verdict: PASS"), "{stdout}");
    let rows = parse(&out.csv);
    assert_eq!(rows.len(), 20 * 7 * 3, "20 selections x 7 p x 3 seeds");
    for name in names() {
        for seed in 1..=3 {
            assert_eq!(series(&rows, &name, seed).len(), 7);
        }
    }
    // Row order: families in table order then mixed; within one, p in schedule order, then seed.
    let order: Vec<(&str, &str, u64)> = rows
        .iter()
        .map(|r| (r.family.as_str(), r.p.as_str(), r.seed))
        .collect();
    let mut expected = Vec::new();
    for name in names() {
        for p in SCHEDULE {
            for seed in 1..=3u64 {
                expected.push((name.clone(), p, seed));
            }
        }
    }
    let expected: Vec<(&str, &str, u64)> = expected
        .iter()
        .map(|(n, p, s)| (n.as_str(), *p, *s))
        .collect();
    assert_eq!(order, expected);
    assert!(out.csv.ends_with('\n') && !out.csv.contains('\r'));
}

#[test]
fn criterion_d_every_row_at_p_zero_scores_one_million() {
    let rows = parse(&first_run().2.csv);
    let at_zero: Vec<&Row> = rows.iter().filter(|r| r.p == "0").collect();
    assert_eq!(at_zero.len(), 20 * 3);
    for r in at_zero {
        assert_eq!(r.score, 1_000_000, "{} seed {}", r.family, r.seed);
        assert_eq!(r.flagged, 0, "{} seed {}", r.family, r.seed);
        assert_eq!(r.recall, None, "no site is corrupted at p=0");
    }
}

#[test]
fn criterion_a_the_mixed_mean_falls_strictly_at_every_step() {
    let rows = parse(&first_run().2.csv);
    let sums: Vec<u64> = (0..SCHEDULE.len())
        .map(|k| (1..=3).map(|seed| series(&rows, "mixed", seed)[k]).sum())
        .collect();
    for k in 0..sums.len() - 1 {
        assert!(
            sums[k + 1] < sums[k],
            "mixed mean does not fall from p={} to p={}: {} -> {}",
            SCHEDULE[k],
            SCHEDULE[k + 1],
            sums[k],
            sums[k + 1]
        );
    }
}

#[test]
fn criteria_b_and_c_mixed_and_every_triggering_family_are_non_increasing_per_seed() {
    let rows = parse(&first_run().2.csv);
    let mut checked = 0;
    for name in names() {
        let gated =
            name == "mixed" || Family::from_name(&name).unwrap().strength() == Strength::Triggering;
        if !gated {
            continue;
        }
        for seed in 1..=3 {
            let s = series(&rows, &name, seed);
            assert!(
                s.windows(2).all(|w| w[1] <= w[0]),
                "{name} seed {seed} is not non-increasing: {s:?}"
            );
            checked += 1;
        }
    }
    assert_eq!(
        checked,
        13 * 3,
        "12 triggering families plus mixed, three seeds each"
    );
}

#[test]
fn recall_at_p_0_05_is_at_least_0_9_where_a_family_declares_a_rule() {
    let rows = parse(&first_run().2.csv);
    for r in rows.iter().filter(|r| r.p == "0.05") {
        match r.recall {
            Some(v) => assert!(v >= 900_000, "{} seed {} recall {v}", r.family, r.seed),
            None => {
                // The cell is empty only when no corrupted site declares a rule: every
                // none-directly family, the unstructured baseline, and bindu_swap, whose rule fires
                // on the 20% keep-both branch and so may not occur in a small sample.
                let empty_ok = matches!(r.family.as_str(), "random_substitution" | "bindu_swap")
                    || Family::from_name(&r.family)
                        .is_some_and(|f| f.strength() == Strength::NoneDirectly);
                assert!(empty_ok, "{} seed {} has no recall", r.family, r.seed);
            }
        }
    }
    // Every other triggering family, and mixed, reports a recall for every seed.
    let reported: std::collections::BTreeSet<&str> = rows
        .iter()
        .filter(|r| r.p == "0.05" && r.recall.is_some())
        .map(|r| r.family.as_str())
        .collect();
    for f in Family::ALL
        .iter()
        .filter(|f| f.strength() == Strength::Triggering)
        .filter(|f| !matches!(f.name(), "random_substitution" | "bindu_swap"))
    {
        assert!(
            reported.contains(f.name()),
            "{} reports no recall",
            f.name()
        );
    }
    assert!(reported.contains("mixed") && reported.contains("bindu_swap"));
}

#[test]
fn none_directly_families_barely_move_the_score() {
    // The documented limitation: structural validation does not see them. A loose bound, not a
    // criterion: no none-directly family loses more than a tenth of the score at p=0.4.
    let rows = parse(&first_run().2.csv);
    for f in Family::ALL
        .iter()
        .filter(|f| f.strength() == Strength::NoneDirectly)
    {
        for seed in 1..=3 {
            let s = series(&rows, f.name(), seed);
            let last = *s.last().unwrap();
            assert!(last >= 900_000, "{} seed {seed} fell to {last}", f.name());
        }
    }
}

#[test]
fn cluster_and_flag_counts_are_consistent_with_the_score() {
    for r in parse(&first_run().2.csv) {
        assert!(r.flagged <= r.cluster_count);
        // penalty is between 200 and 1000 per flagged cluster, so the loss is bounded both ways.
        let loss = 1_000_000 - r.score;
        assert!(
            loss + 1 >= r.flagged * 200 * 1000 / r.cluster_count.max(1),
            "{}",
            r.family
        );
        assert!(
            loss <= r.flagged * 1000 * 1000 / r.cluster_count.max(1) + 1,
            "{}",
            r.family
        );
    }
}

// ---- determinism and the committed files --------------------------------------------------------

#[test]
fn a_second_run_is_byte_identical() {
    let first = &first_run().2;
    let (r, second) = bench_into("bench-second");
    assert_eq!(r.code, 0);
    assert_eq!(second.csv, first.csv, "CSV differs between runs");
    assert_eq!(second.svg, first.svg, "SVG differs between runs");
}

#[test]
fn the_committed_csv_and_svg_are_what_the_command_produces() {
    let first = &first_run().2;
    let csv = std::fs::read_to_string(root().join("docs/score-vs-noise.csv"))
        .expect("docs/score-vs-noise.csv is committed");
    let svg = std::fs::read_to_string(root().join("docs/score-vs-noise.svg"))
        .expect("docs/score-vs-noise.svg is committed");
    assert_eq!(csv, first.csv, "regenerate with the command in the README");
    assert_eq!(svg, first.svg, "regenerate with the command in the README");
}

// ---- the SVG ------------------------------------------------------------------------------------

#[test]
fn the_svg_is_small_inert_and_has_no_external_reference() {
    let svg = &first_run().2.svg;
    assert!(svg.len() < 200_000, "{} bytes", svg.len());
    assert!(svg.starts_with("<svg "), "starts with the root element");
    assert!(svg.ends_with("</svg>\n"));
    let lower = svg.to_lowercase();
    for banned in [
        "<script",
        "<foreignobject",
        "href",
        "<iframe",
        "<object",
        "<embed",
        "<image",
        "@import",
        "javascript:",
        "data:",
        "<style",
        "<link",
        "<use",
    ] {
        assert!(!lower.contains(banned), "svg contains {banned}");
    }
    // No event-handler attribute: ` on<letters>=`.
    let bytes = lower.as_bytes();
    for i in 0..bytes.len().saturating_sub(4) {
        if bytes[i] == b' ' && bytes[i + 1] == b'o' && bytes[i + 2] == b'n' {
            let rest = &lower[i + 3..];
            let name_len = rest.chars().take_while(char::is_ascii_lowercase).count();
            assert!(
                !rest[name_len..].starts_with('='),
                "event handler attribute at byte {i}"
            );
        }
    }
    // The only URL is the SVG namespace declaration; once it is removed nothing external remains.
    let stripped = svg.replace("xmlns=\"http://www.w3.org/2000/svg\"", "");
    for banned in ["http:", "https:", "//", "url(", "xlink"] {
        assert!(!stripped.contains(banned), "svg contains {banned}");
    }
    assert!(svg.matches("xmlns=").count() == 1);
}

#[test]
fn the_svg_text_is_escaped_and_coordinates_are_integers() {
    let svg = &first_run().2.svg;
    // Every '&' starts an entity, and no text node contains '<' or '>'.
    for (i, _) in svg.match_indices('&') {
        let rest = &svg[i..];
        assert!(
            ["&amp;", "&lt;", "&gt;", "&quot;", "&apos;"]
                .iter()
                .any(|e| rest.starts_with(e)),
            "bare ampersand near {:?}",
            &svg[i..svg.len().min(i + 12)]
        );
    }
    // Coordinates in numeric attributes are integers.
    for attr in [
        "x",
        "y",
        "x1",
        "y1",
        "x2",
        "y2",
        "cx",
        "cy",
        "r",
        "width",
        "height",
        "stroke-width",
        "points",
        "viewBox",
    ] {
        let needle = format!(" {attr}=\"");
        for (i, _) in svg.match_indices(&needle) {
            let value = svg[i + needle.len()..].split('"').next().unwrap();
            assert!(!value.contains('.'), "non-integer {attr}=\"{value}\"");
            assert!(
                value
                    .chars()
                    .all(|c| c.is_ascii_digit() || c == ' ' || c == ',' || c == '-'),
                "{attr}=\"{value}\""
            );
        }
    }
    // It carries a title and a description for assistive technology, and the chart's own labels.
    assert!(svg.contains("<title"));
    assert!(svg.contains("<desc"));
    assert!(svg.contains("role=\"img\""));
    assert!(svg.contains("mixed"));
    assert!(svg.contains("noise level"));
}

#[test]
fn the_svg_has_no_timestamp_or_machine_specific_text() {
    let svg = &first_run().2.svg;
    for banned in ["/Users", "/home", "C:\\", "2026-", "T00:", "UTC", "GMT"] {
        assert!(!svg.contains(banned), "svg contains {banned}");
    }
}

// ---- --verify and the exit code ------------------------------------------------------------------

fn verify(csv: &str, name: &str) -> common::Run {
    let path = scratch(name).join("in.csv");
    std::fs::write(&path, csv).unwrap();
    run(&["bench", "--verify", path.to_str().unwrap()], b"")
}

fn rewrite(csv: &str, family: &str, p: &str, seed: u64, score: u64) -> String {
    let mut out = String::new();
    for (n, line) in csv.lines().enumerate() {
        let f: Vec<&str> = line.split(',').collect();
        if n > 0 && f[0] == family && f[1] == p && f[2] == seed.to_string() {
            out.push_str(&format!(
                "{},{},{},{},{},{},{}\n",
                f[0], f[1], f[2], f[3], f[4], score, f[6]
            ));
        } else {
            out.push_str(line);
            out.push('\n');
        }
    }
    out
}

#[test]
fn verify_passes_on_the_real_csv() {
    let r = verify(&first_run().2.csv, "verify-ok");
    assert_eq!(r.code, 0, "{}{}", r.out(), r.stderr);
    assert!(r.out().contains("verdict: PASS"));
}

#[test]
fn verify_exits_1_on_an_injected_non_monotone_triggering_family() {
    let csv = &first_run().2.csv;
    let rows = parse(csv);
    let s = series(&rows, "matra_double", 2);
    // Make the score at p=0.1 higher than at p=0.05.
    let bad = rewrite(csv, "matra_double", "0.1", 2, s[3] + 5);
    let r = verify(&bad, "verify-c");
    assert_eq!(r.code, 1);
    let text = format!("{}{}", r.out(), r.stderr);
    assert!(text.contains("verdict: FAIL"), "{text}");
    assert!(
        text.contains("(c)") && text.contains("matra_double") && text.contains("seed 2"),
        "{text}"
    );
}

#[test]
fn verify_exits_1_when_mixed_rises_for_one_seed_or_the_mean_stops_falling() {
    let csv = &first_run().2.csv;
    let rows = parse(csv);
    let s = series(&rows, "mixed", 1);
    let rise = rewrite(csv, "mixed", "0.02", 1, s[1] + 1);
    let r = verify(&rise, "verify-b");
    assert_eq!(r.code, 1);
    assert!(format!("{}{}", r.out(), r.stderr).contains("(b)"));

    // Flatten the mean between p=0.2 and p=0.4 by copying each seed's p=0.2 score to p=0.4.
    let mut flat = csv.clone();
    for seed in 1..=3 {
        let at = series(&rows, "mixed", seed)[5];
        flat = rewrite(&flat, "mixed", "0.4", seed, at);
    }
    let r = verify(&flat, "verify-a");
    assert_eq!(r.code, 1);
    assert!(format!("{}{}", r.out(), r.stderr).contains("(a)"));
}

#[test]
fn verify_exits_1_when_a_score_at_p_zero_is_not_one_million() {
    let csv = &first_run().2.csv;
    let bad = rewrite(csv, "digit_danda", "0", 3, 999_999);
    let r = verify(&bad, "verify-d");
    assert_eq!(r.code, 1);
    assert!(format!("{}{}", r.out(), r.stderr).contains("(d)"));
}

#[test]
fn verify_does_not_gate_none_directly_families() {
    let csv = &first_run().2.csv;
    let rows = parse(csv);
    let s = series(&rows, "ocr_confusion", 1);
    let wobble = rewrite(csv, "ocr_confusion", "0.4", 1, s[0]);
    let r = verify(&wobble, "verify-none");
    assert_eq!(r.code, 0, "{}{}", r.out(), r.stderr);
}

#[test]
fn verify_refuses_an_incomplete_or_malformed_csv() {
    let csv = &first_run().2.csv;
    let truncated: String = csv.lines().take(50).map(|l| format!("{l}\n")).collect();
    assert_eq!(verify(&truncated, "verify-trunc").code, 1);
    assert_eq!(verify("not,a,benchmark\n1,2,3\n", "verify-junk").code, 1);
    assert_eq!(
        run(&["bench", "--verify", "/no/such/file.csv"], b"").code,
        1
    );
}

// ---- arguments ----------------------------------------------------------------------------------

#[test]
fn bad_arguments_exit_2_and_a_missing_corpus_exits_1() {
    let d = scratch("bench-args");
    let (csv, svg) = (d.join("a.csv"), d.join("a.svg"));
    let (csv, svg) = (csv.to_str().unwrap(), svg.to_str().unwrap());
    let corpus = root().join("bench/corpus/clean.txt");
    let corpus = corpus.to_str().unwrap();
    let cases: Vec<Vec<&str>> = vec![
        vec!["bench"],
        vec!["bench", "--corpus", corpus],
        vec![
            "bench", "--corpus", corpus, "--seeds", "1,x", "--csv", csv, "--svg", svg,
        ],
        vec![
            "bench", "--corpus", corpus, "--seeds", "", "--csv", csv, "--svg", svg,
        ],
        vec![
            "bench", "--corpus", corpus, "--seeds", "1,1", "--csv", csv, "--svg", svg,
        ],
        vec!["bench", "--corpus", corpus, "--seeds", "1", "--csv", csv],
        vec!["bench", "--verify", csv, "--corpus", corpus],
    ];
    for args in cases {
        let r = run(&args, b"");
        assert_eq!(r.code, 2, "{args:?}: {}", r.stderr);
    }
    let r = run(
        &[
            "bench",
            "--corpus",
            "/no/such/corpus.txt",
            "--seeds",
            "1",
            "--csv",
            csv,
            "--svg",
            svg,
        ],
        b"",
    );
    assert_eq!(r.code, 1);
    assert!(r.stderr.contains("/no/such/corpus.txt"), "{}", r.stderr);
}
