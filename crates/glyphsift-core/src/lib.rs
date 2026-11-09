//! glyphsift-core: is extracted Indic text clean enough to trust or train on?
//!
//! Sprint 1 ships the type definitions, the segmentation helper and the tests-first case table;
//! [`validate`] returns [`Error::Unimplemented`] until the Devanagari validator lands in Sprint 2
//! (see `docs/devanagari-rules.md` and `tests/cases/devanagari.toml`).
//!
//! Determinism contract: no `HashMap`/`HashSet` (enforced by `clippy.toml`), no clock, no
//! environment, no file system, no platform `libm`. The same input gives byte-identical JSON on
//! native, Python and WASM builds.

#![forbid(unsafe_code)]

pub mod report;

pub use report::{Cluster, Issue, IssueKind, REPORT_SPEC, Report, Summary};
use unicode_segmentation::UnicodeSegmentation;

/// Errors from [`validate`].
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum Error {
    /// The validator is not implemented yet. `since` names the sprint it lands in.
    #[error("glyphsift validator is not implemented yet (lands in {since})")]
    Unimplemented {
        /// The sprint the implementation is scheduled for.
        since: &'static str,
    },
}

/// Validate `text` against the Devanagari grapheme-cluster rules.
///
/// Sprint 1: always returns `Err(Error::Unimplemented { since: "Sprint 2" })`. The signature is
/// frozen now so the CLI, Python and WASM bindings and the tests-first case table build against it.
pub fn validate(text: &str) -> Result<Report, Error> {
    let _ = text;
    Err(Error::Unimplemented { since: "Sprint 2" })
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
    fn validate_is_unimplemented_until_sprint_2() {
        assert_eq!(
            validate("नमस्ते"),
            Err(Error::Unimplemented { since: "Sprint 2" })
        );
        assert_eq!(
            validate(""),
            Err(Error::Unimplemented { since: "Sprint 2" })
        );
    }

    #[test]
    fn error_message_names_the_sprint() {
        let e = validate("x").unwrap_err();
        assert!(e.to_string().contains("Sprint 2"));
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
