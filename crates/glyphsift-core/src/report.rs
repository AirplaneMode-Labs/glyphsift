//! Report types: what `validate` returns once the Sprint 2 validator lands. They are defined now so
//! the CLI, Python and WASM bindings compile and serialise, and so the tests-first case table in
//! `tests/cases/devanagari.toml` can name every issue kind.
//!
//! Canonical JSON rule: a report is serialised with `serde_json::to_string` (compact, no
//! whitespace). Struct fields serialise in declaration order, every collection is a `Vec` in input
//! order, and no floating-point values appear, so the bytes are identical on native, Python and
//! WASM builds.

use serde::{Deserialize, Serialize};

/// Spec discriminator carried by every report (major.minor; patch never changes the wire format).
pub const REPORT_SPEC: &str = "glyphsift.report/0.1";

/// Everything `validate` says about one piece of text.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Report {
    /// Always [`REPORT_SPEC`].
    pub spec: String,
    /// Script the rules were applied for. Only `"devanagari"` in 0.1.
    pub script: String,
    /// Number of Unicode scalar values in the input.
    pub code_points: usize,
    /// UAX #29 extended grapheme clusters, in input order.
    pub clusters: Vec<Cluster>,
    /// Every rule violation found, in input order (by cluster index, then by position).
    pub issues: Vec<Issue>,
    /// Aggregates, so a caller need not walk the vectors.
    pub summary: Summary,
}

/// One extended grapheme cluster of the input.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Cluster {
    /// Zero-based position in [`Report::clusters`].
    pub index: usize,
    /// The cluster's text, exactly as in the input.
    pub text: String,
    /// Byte offset of the cluster's first code unit in the UTF-8 input.
    pub start: usize,
    /// Byte offset one past the cluster's last code unit.
    pub end: usize,
    /// Code points as `U+XXXX`, for display and for tests that cannot show invisible marks.
    pub code_points: Vec<String>,
}

/// One rule violation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Issue {
    /// Which rule fired.
    pub kind: IssueKind,
    /// Index into [`Report::clusters`] of the cluster the issue was found in.
    pub cluster: usize,
    /// The offending code point as `U+XXXX`, if the rule names one.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code_point: Option<String>,
}

/// Counts over the whole input.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Summary {
    pub cluster_count: usize,
    pub issue_count: usize,
    /// Clusters with at least one issue.
    pub flagged_clusters: usize,
}

/// The Devanagari rules. Each variant is one rule; the names are the stable wire format
/// (`snake_case`) and the names used in `tests/cases/devanagari.toml`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum IssueKind {
    /// A matra (dependent vowel sign) with no consonant to attach to: at cluster start, after a
    /// dead consonant (consonant + virama), or on a non-letter base.
    DependentVowelWithoutBase,
    /// Anusvara, chandrabindu, visarga, nukta or a Vedic sign with no base character in its cluster.
    StrayCombiningMark,
    /// Two or more matras in one cluster.
    DoubleMatra,
    /// Two nuktas on one consonant (including nukta on a precomposed U+0958..U+095F consonant).
    DoubleNukta,
    /// A nukta that comes after a matra instead of directly after its consonant.
    NuktaAfterMatra,
    /// A nukta on an independent vowel, digit, sign or other non-consonant.
    NuktaOnNonConsonant,
    /// A virama with no consonant directly before it (cluster start, after a vowel, after a virama).
    ViramaWithoutConsonant,
    /// A virama directly after a matra (the syllable already has its vowel).
    ViramaAfterMatra,
    /// Anusvara, chandrabindu or visarga before a matra in the same cluster.
    SignBeforeMatra,
    /// More than one of anusvara / chandrabindu in one cluster.
    MultipleAnusvaraLike,
    /// Visarga followed by anusvara or chandrabindu (the reverse order is valid).
    VisargaBeforeAnusvara,
    /// A matra attached to an independent vowel letter.
    VowelSignOnIndependentVowel,
    /// ZWJ or ZWNJ anywhere other than directly after a virama.
    ZwjZwnjMisplaced,
    /// A cluster whose base is from another script carrying Devanagari combining marks (or the
    /// reverse).
    MixedScriptInCluster,
    /// A code point outside the validator's tables: U+FFFD, private use, unassigned, or a
    /// Devanagari-block code point with no role.
    UnexpectedCodePoint,
    /// A C0/C1 control (other than TAB, LF, CR), a bidi format control, or a BOM after offset 0.
    ControlCharacter,
}

impl IssueKind {
    /// Every kind, in declaration order. The case table must cover each of these at least once.
    pub const ALL: [IssueKind; 16] = [
        IssueKind::DependentVowelWithoutBase,
        IssueKind::StrayCombiningMark,
        IssueKind::DoubleMatra,
        IssueKind::DoubleNukta,
        IssueKind::NuktaAfterMatra,
        IssueKind::NuktaOnNonConsonant,
        IssueKind::ViramaWithoutConsonant,
        IssueKind::ViramaAfterMatra,
        IssueKind::SignBeforeMatra,
        IssueKind::MultipleAnusvaraLike,
        IssueKind::VisargaBeforeAnusvara,
        IssueKind::VowelSignOnIndependentVowel,
        IssueKind::ZwjZwnjMisplaced,
        IssueKind::MixedScriptInCluster,
        IssueKind::UnexpectedCodePoint,
        IssueKind::ControlCharacter,
    ];

    /// The wire name (`snake_case`), identical to the serde representation.
    pub fn name(self) -> &'static str {
        match self {
            IssueKind::DependentVowelWithoutBase => "dependent_vowel_without_base",
            IssueKind::StrayCombiningMark => "stray_combining_mark",
            IssueKind::DoubleMatra => "double_matra",
            IssueKind::DoubleNukta => "double_nukta",
            IssueKind::NuktaAfterMatra => "nukta_after_matra",
            IssueKind::NuktaOnNonConsonant => "nukta_on_non_consonant",
            IssueKind::ViramaWithoutConsonant => "virama_without_consonant",
            IssueKind::ViramaAfterMatra => "virama_after_matra",
            IssueKind::SignBeforeMatra => "sign_before_matra",
            IssueKind::MultipleAnusvaraLike => "multiple_anusvara_like",
            IssueKind::VisargaBeforeAnusvara => "visarga_before_anusvara",
            IssueKind::VowelSignOnIndependentVowel => "vowel_sign_on_independent_vowel",
            IssueKind::ZwjZwnjMisplaced => "zwj_zwnj_misplaced",
            IssueKind::MixedScriptInCluster => "mixed_script_in_cluster",
            IssueKind::UnexpectedCodePoint => "unexpected_code_point",
            IssueKind::ControlCharacter => "control_character",
        }
    }

    /// Parse a wire name.
    pub fn from_name(name: &str) -> Option<IssueKind> {
        IssueKind::ALL.into_iter().find(|k| k.name() == name)
    }
}

impl core::fmt::Display for IssueKind {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str(self.name())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_round_trip_through_serde_and_from_name() {
        for kind in IssueKind::ALL {
            let json = serde_json::to_string(&kind).unwrap();
            assert_eq!(json, format!("\"{}\"", kind.name()));
            let back: IssueKind = serde_json::from_str(&json).unwrap();
            assert_eq!(back, kind);
            assert_eq!(IssueKind::from_name(kind.name()), Some(kind));
        }
        assert_eq!(IssueKind::from_name("not_a_rule"), None);
    }

    #[test]
    fn all_is_complete_and_distinct() {
        let mut names: Vec<&str> = IssueKind::ALL.iter().map(|k| k.name()).collect();
        names.sort_unstable();
        names.dedup();
        assert_eq!(names.len(), 16);
    }

    #[test]
    fn report_serialises_compactly_in_field_order() {
        let report = Report {
            spec: REPORT_SPEC.to_owned(),
            script: "devanagari".to_owned(),
            code_points: 1,
            clusters: vec![Cluster {
                index: 0,
                text: "\u{093F}".to_owned(),
                start: 0,
                end: 3,
                code_points: vec!["U+093F".to_owned()],
            }],
            issues: vec![Issue {
                kind: IssueKind::DependentVowelWithoutBase,
                cluster: 0,
                code_point: Some("U+093F".to_owned()),
            }],
            summary: Summary {
                cluster_count: 1,
                issue_count: 1,
                flagged_clusters: 1,
            },
        };
        let json = serde_json::to_string(&report).unwrap();
        assert_eq!(
            json,
            "{\"spec\":\"glyphsift.report/0.1\",\"script\":\"devanagari\",\"code_points\":1,\
             \"clusters\":[{\"index\":0,\"text\":\"ि\",\"start\":0,\"end\":3,\"code_points\":[\"U+093F\"]}],\
             \"issues\":[{\"kind\":\"dependent_vowel_without_base\",\"cluster\":0,\"code_point\":\"U+093F\"}],\
             \"summary\":{\"cluster_count\":1,\"issue_count\":1,\"flagged_clusters\":1}}"
        );
        let back: Report = serde_json::from_str(&json).unwrap();
        assert_eq!(back, report);
    }
}
