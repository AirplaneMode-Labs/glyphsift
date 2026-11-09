//! Harness for the Devanagari validator.
//!
//! `cases/devanagari.toml` is the specification: the input, the expected UAX #29 extended grapheme
//! clusters and the expected issues as `{kind, cluster}`. The tests prove the table is real (it
//! parses, names every `IssueKind`, and its expected clusters are what the segmenter produces) and
//! that `validate()` agrees with every case.
//!
//! Table extensions beyond the original 77 cases, all optional per case:
//! - `repeat = { unit, count }` appends `unit` `count` times to `input` (a long run cannot be
//!   written out by hand); such a case gives `cluster_count` instead of `clusters`.
//! - an expected issue may carry `count` (default 1): that many identical `{kind, cluster}` issues.

use std::collections::BTreeSet;

use glyphsift_core::{IssueKind, clusters, validate};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct Table {
    case: Vec<Case>,
}

#[derive(Debug, Deserialize)]
struct Case {
    name: String,
    input: String,
    #[serde(default)]
    repeat: Option<Repeat>,
    #[serde(default)]
    clusters: Vec<String>,
    #[serde(default)]
    cluster_count: Option<usize>,
    issues: Vec<ExpectedIssue>,
    #[allow(dead_code)]
    note: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Repeat {
    unit: String,
    count: usize,
}

#[derive(Debug, Deserialize)]
struct ExpectedIssue {
    kind: String,
    cluster: usize,
    #[serde(default = "one")]
    count: usize,
}

fn one() -> usize {
    1
}

const TABLE: &str = include_str!("cases/devanagari.toml");

fn load() -> Vec<Case> {
    let table: Table = toml::from_str(TABLE).expect("cases/devanagari.toml parses");
    table.case
}

impl Case {
    /// The full input: `input` followed by the repeated unit, if any.
    fn full_input(&self) -> String {
        match &self.repeat {
            Some(r) => format!("{}{}", self.input, r.unit.repeat(r.count)),
            None => self.input.clone(),
        }
    }

    /// Expected cluster count, from the explicit list or from `cluster_count`.
    fn expected_cluster_count(&self) -> usize {
        self.cluster_count.unwrap_or(self.clusters.len())
    }
}

#[test]
fn table_parses_has_at_least_77_cases_and_names_every_issue_kind() {
    let cases = load();
    assert!(
        cases.len() >= 77,
        "expected at least 77 cases, found {}",
        cases.len()
    );
    // The Sprint 2 additions this lane promised must stay in the table.
    let names: BTreeSet<&str> = cases.iter().map(|c| c.name.as_str()).collect();
    for required in [
        "crlf_line_ending",
        "bom_at_offset_zero",
        "bom_mid_text",
        "marks_2000_matra_run",
    ] {
        assert!(names.contains(required), "case {required} is missing");
    }

    let mut seen_names = BTreeSet::new();
    let mut kinds_seen = BTreeSet::new();
    for case in &cases {
        assert!(
            seen_names.insert(case.name.as_str()),
            "duplicate case name {}",
            case.name
        );
        for issue in &case.issues {
            let kind = IssueKind::from_name(&issue.kind)
                .unwrap_or_else(|| panic!("{}: unknown issue kind {}", case.name, issue.kind));
            kinds_seen.insert(kind);
            assert!(
                issue.cluster < case.expected_cluster_count(),
                "{}: issue cluster index {} out of range ({} clusters)",
                case.name,
                issue.cluster,
                case.expected_cluster_count()
            );
        }
        if case.repeat.is_none() {
            // Clusters must concatenate back to the input exactly.
            assert_eq!(
                case.clusters.concat(),
                case.input,
                "{}: clusters do not concatenate to the input",
                case.name
            );
        } else {
            assert!(
                case.cluster_count.is_some() && case.clusters.is_empty(),
                "{}: a repeat case gives cluster_count, not clusters",
                case.name
            );
        }
    }
    for kind in IssueKind::ALL {
        assert!(
            kinds_seen.contains(&kind),
            "issue kind {} has no case in the table",
            kind.name()
        );
    }
}

#[test]
fn expected_clusters_are_uax29_extended_grapheme_clusters() {
    for case in load() {
        let got: Vec<String> = clusters(&case.full_input())
            .into_iter()
            .map(|c| c.text)
            .collect();
        if case.repeat.is_some() {
            assert_eq!(
                got.len(),
                case.expected_cluster_count(),
                "{}: UAX #29 cluster count differs from the table",
                case.name
            );
        } else {
            assert_eq!(
                got, case.clusters,
                "{}: UAX #29 segmentation differs from the table",
                case.name
            );
        }
    }
}

/// The real harness: every case, every expected cluster and issue. Prints `table cases passing:
/// N/M` (visible with `--nocapture`) so a rule-by-rule run can log its progress.
#[test]
fn validator_matches_case_table() {
    let cases = load();
    let total = cases.len();
    let mut failures = Vec::new();
    let mut passing = 0usize;
    for case in &cases {
        let before = failures.len();
        let input = case.full_input();
        let report = match validate(&input) {
            Ok(r) => r,
            Err(e) => {
                failures.push(format!("{}: validate() failed: {e}", case.name));
                continue;
            }
        };
        if case.repeat.is_none() {
            let got_clusters: Vec<String> =
                report.clusters.iter().map(|c| c.text.clone()).collect();
            if got_clusters != case.clusters {
                failures.push(format!(
                    "{}: clusters {:?} != expected {:?}",
                    case.name, got_clusters, case.clusters
                ));
            }
        } else if report.clusters.len() != case.expected_cluster_count() {
            failures.push(format!(
                "{}: {} clusters != expected {}",
                case.name,
                report.clusters.len(),
                case.expected_cluster_count()
            ));
        }
        let got_issues: Vec<(usize, &str)> = report
            .issues
            .iter()
            .map(|i| (i.cluster, i.kind.name()))
            .collect();
        let mut got_sorted = got_issues.clone();
        got_sorted.sort_unstable();
        let mut want_issues: Vec<(usize, &str)> = Vec::new();
        for i in &case.issues {
            for _ in 0..i.count {
                want_issues.push((i.cluster, i.kind.as_str()));
            }
        }
        want_issues.sort_unstable();
        if got_sorted != want_issues {
            // Large runs would flood the log; show the head of each side.
            let head =
                |v: &[(usize, &str)]| format!("{:?} (len {})", &v[..v.len().min(6)], v.len());
            failures.push(format!(
                "{}: issues {} != expected {}",
                case.name,
                head(&got_sorted),
                head(&want_issues)
            ));
        }
        // The report lists issues in input order: by cluster, never going backwards.
        if got_issues.windows(2).any(|w| w[0].0 > w[1].0) {
            failures.push(format!("{}: issues are not in cluster order", case.name));
        }
        if report.summary.cluster_count != report.clusters.len()
            || report.summary.issue_count != report.issues.len()
        {
            failures.push(format!(
                "{}: summary counts do not match vectors",
                case.name
            ));
        }
        if failures.len() == before {
            passing += 1;
        }
    }
    println!("table cases passing: {passing}/{total}");
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// A fixed set of inputs that must come out clean: the table's own valid cases, validated as a
/// concatenation would be, are covered above; this pins the empty string and pure whitespace.
#[test]
fn empty_and_whitespace_only_text_has_no_issues() {
    for text in ["", " ", "\n", "\r\n", "\t \n\r\n"] {
        let report = validate(text).expect("validates");
        assert!(report.issues.is_empty(), "{text:?} produced issues");
        assert_eq!(report.summary.issue_count, 0);
    }
}
