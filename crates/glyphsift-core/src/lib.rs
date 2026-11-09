//! glyphsift-core: is extracted Indic text clean enough to trust or train on?
//!
//! [`validate`] splits text into UAX #29 grapheme clusters and checks each against the Devanagari
//! cluster grammar and sixteen rules (`docs/devanagari-rules.md`); `tests/cases/devanagari.toml` is
//! the executable form of the rules.
//!
//! Determinism contract: no hash-based collections (enforced by `clippy.toml`), no floating point,
//! no clock, no environment, no file system, no platform `libm`. The same input gives
//! byte-identical JSON on native, Python and WASM builds.

#![forbid(unsafe_code)]

#[cfg(feature = "corrupt")]
pub mod corrupt;
pub mod report;
mod rules;
mod score;
mod tables;

pub use report::{Cluster, Issue, IssueKind, LineSummary, REPORT_SPEC, Report, Score, Summary};
pub use score::{MAX_WEIGHT, Weights, WeightsError, score_ppm};
use unicode_segmentation::UnicodeSegmentation;

/// Errors from [`validate`].
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum Error {
    /// The input is longer than [`MAX_INPUT_BYTES`].
    #[error("input is too large: {bytes} bytes, the limit is {max}")]
    InputTooLarge {
        /// Length of the rejected input in bytes.
        bytes: usize,
        /// The limit, [`MAX_INPUT_BYTES`].
        max: usize,
    },
}

/// Longest input `validate` accepts, in bytes of UTF-8 (4 MiB). A report carries one record per
/// grapheme cluster, so memory grows with the input; split larger corpora by document or line.
pub const MAX_INPUT_BYTES: usize = 4 * 1024 * 1024;

/// Validate `text` against the Devanagari grapheme-cluster rules (`docs/devanagari-rules.md`).
///
/// The text is split into UAX #29 extended grapheme clusters; each cluster is parsed once against
/// the cluster grammar and checked by the sixteen rules. The result is deterministic: the same
/// text gives the same report on every platform.
///
/// # Errors
///
/// [`Error::InputTooLarge`] when `text` is longer than [`MAX_INPUT_BYTES`].
pub fn validate(text: &str) -> Result<Report, Error> {
    if text.len() > MAX_INPUT_BYTES {
        return Err(Error::InputTooLarge {
            bytes: text.len(),
            max: MAX_INPUT_BYTES,
        });
    }
    let clusters = clusters(text);
    let mut issues = Vec::new();
    let mut slots = Vec::new();
    let mut found = Vec::new();
    for cluster in &clusters {
        rules::check_cluster(&cluster.text, cluster.start, &mut slots, &mut found);
        for &(kind, cp) in &found {
            issues.push(Issue {
                kind,
                cluster: cluster.index,
                code_point: Some(format!("U+{:04X}", cp as u32)),
            });
        }
    }
    let (summary, lines, score) = score::summarise(&clusters, &issues, Weights::builtin());
    Ok(Report {
        spec: REPORT_SPEC.to_owned(),
        script: "devanagari".to_owned(),
        code_points: text.chars().count(),
        clusters,
        issues,
        summary,
        lines,
        score,
    })
}

/// The UAX #29 extended grapheme clusters of `text`, in order, with their byte offsets.
///
/// This is the segmentation the Sprint 2 validator uses (unicode-segmentation 1.13.x, including
/// the Unicode 15.1 GB9c conjunct rule, so `क्ष` is one cluster). It is exposed now so the case
/// table's expected clusters can be checked against the library before any rule exists.
pub fn clusters(text: &str) -> Vec<Cluster> {
    text.grapheme_indices(true)
        .enumerate()
        .map(|(index, (start, g))| Cluster {
            index,
            text: g.to_owned(),
            start,
            end: start + g.len(),
            code_points: g.chars().map(|c| format!("U+{:04X}", c as u32)).collect(),
        })
        .collect()
}

/// Canonical JSON for a report: compact `serde_json`, fields in declaration order.
pub fn to_canonical_json(report: &Report) -> String {
    // Serialising a struct of strings, integers and vectors cannot fail.
    serde_json::to_string(report).expect("report serialisation is infallible")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_reports_clean_text_with_no_issues() {
        let report = validate("नमस्ते।").expect("validates");
        assert_eq!(report.summary.cluster_count, 4);
        assert!(report.issues.is_empty());
        let empty = validate("").expect("validates");
        assert_eq!(empty.summary.cluster_count, 0);
    }

    #[test]
    fn validate_refuses_input_over_the_size_limit() {
        let big = "क".repeat(MAX_INPUT_BYTES / 3 + 1);
        let err = validate(&big).unwrap_err();
        assert!(matches!(err, Error::InputTooLarge { .. }));
        assert!(err.to_string().contains("too large"));
    }

    #[test]
    fn clusters_follow_uax29_with_conjuncts() {
        let c = clusters("नमस्ते।");
        let texts: Vec<&str> = c.iter().map(|c| c.text.as_str()).collect();
        assert_eq!(texts, ["न", "म", "स्ते", "।"]);
        assert_eq!(c[2].start, 6);
        assert_eq!(c[2].end, 18);
        assert_eq!(c[2].code_points, ["U+0938", "U+094D", "U+0924", "U+0947"]);
        assert!(clusters("").is_empty());
    }
}
