//! Tests-first harness for the Devanagari validator (Sprint 2).
//!
//! `cases/devanagari.toml` is the specification. The non-ignored tests prove the table is real:
//! it parses, has at least 60 cases, names every `IssueKind`, and its expected clusters are what
//! the UAX #29 segmenter produces. The `#[ignore]`d test runs the validator over every case and
//! fails today, because `validate` returns `Unimplemented` until Sprint 2.

use std::collections::BTreeSet;

use glyphsift_core::{Error, IssueKind, clusters, validate};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct Table {
    case: Vec<Case>,
}

#[derive(Debug, Deserialize)]
struct Case {
    name: String,
    input: String,
    clusters: Vec<String>,
    issues: Vec<ExpectedIssue>,
    #[allow(dead_code)]
    note: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ExpectedIssue {
    kind: String,
    cluster: usize,
}

const TABLE: &str = include_str!("cases/devanagari.toml");

fn load() -> Vec<Case> {
    let table: Table = toml::from_str(TABLE).expect("cases/devanagari.toml parses");
    table.case
}

#[test]
fn table_parses_has_60_cases_and_names_every_issue_kind() {
    let cases = load();
    assert!(
        cases.len() >= 60,
        "expected at least 60 cases, found {}",
        cases.len()
    );

    let mut names = BTreeSet::new();
    let mut kinds_seen = BTreeSet::new();
    for case in &cases {
        assert!(
            names.insert(case.name.as_str()),
            "duplicate case name {}",
            case.name
        );
        for issue in &case.issues {
            let kind = IssueKind::from_name(&issue.kind)
                .unwrap_or_else(|| panic!("{}: unknown issue kind {}", case.name, issue.kind));
            kinds_seen.insert(kind);
            assert!(
                issue.cluster < case.clusters.len(),
                "{}: issue cluster index {} out of range ({} clusters)",
                case.name,
                issue.cluster,
                case.clusters.len()
            );
        }
        // Clusters must concatenate back to the input exactly.
        assert_eq!(
            case.clusters.concat(),
            case.input,
            "{}: clusters do not concatenate to the input",
            case.name
        );
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
        let got: Vec<String> = clusters(&case.input).into_iter().map(|c| c.text).collect();
        assert_eq!(
            got, case.clusters,
            "{}: UAX #29 segmentation differs from the table",
            case.name
        );
    }
}

#[test]
fn validate_is_unimplemented_for_every_case_until_sprint_2() {
    for case in load() {
        assert_eq!(
            validate(&case.input),
            Err(Error::Unimplemented { since: "Sprint 2" }),
            "{}: validate() must return Unimplemented in Sprint 1",
            case.name
        );
    }
}

/// The real harness. Run with `cargo test -- --ignored`; it fails until the validator exists.
#[test]
#[ignore = "Sprint 2: validator not implemented"]
fn validator_matches_case_table() {
    let mut failures = Vec::new();
    for case in load() {
        let report = match validate(&case.input) {
            Ok(r) => r,
            Err(e) => {
                failures.push(format!("{}: validate() failed: {e}", case.name));
                continue;
            }
        };
        let got_clusters: Vec<String> = report.clusters.iter().map(|c| c.text.clone()).collect();
        if got_clusters != case.clusters {
            failures.push(format!(
                "{}: clusters {:?} != expected {:?}",
                case.name, got_clusters, case.clusters
            ));
        }
        let mut got_issues: Vec<(usize, &str)> = report
            .issues
            .iter()
            .map(|i| (i.cluster, i.kind.name()))
            .collect();
        got_issues.sort_unstable();
        let mut want_issues: Vec<(usize, &str)> = case
            .issues
            .iter()
            .map(|i| (i.cluster, i.kind.as_str()))
            .collect();
        want_issues.sort_unstable();
        if got_issues != want_issues {
            failures.push(format!(
                "{}: issues {:?} != expected {:?}",
                case.name, got_issues, want_issues
            ));
        }
        if report.summary.cluster_count != report.clusters.len()
            || report.summary.issue_count != report.issues.len()
        {
            failures.push(format!(
                "{}: summary counts do not match vectors",
                case.name
            ));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
