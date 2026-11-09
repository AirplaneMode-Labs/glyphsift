//! The document score and per-line scores.
//!
//! Every figure is an integer. A flagged cluster costs the largest weight among its issues; the
//! weights are the integers in `weights/devanagari.toml`, read by the strict parser below (the
//! file is also valid TOML, which a test checks). The penalty is spread over the clusters:
//!
//! ```text
//! ppm = 1_000_000 - floor(penalty * 1000 / cluster_count)   (saturating; 1_000_000 when empty)
//! ```
//!
//! so one broken cluster out of four, at weight 1000, scores 750_000. There is no floating point
//! anywhere on this path, which is what keeps native, Python and WASM reports byte-identical.

use std::collections::BTreeMap;
use std::sync::OnceLock;

use crate::report::{Cluster, Issue, IssueKind, LineSummary, Score, Summary};

/// Largest allowed weight; weights are in `1..=MAX_WEIGHT`.
pub const MAX_WEIGHT: u32 = 1000;

/// The weights file compiled into the crate.
const WEIGHTS_TOML: &str = include_str!("../weights/devanagari.toml");

/// Why a weights file was refused.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum WeightsError {
    /// A line is not `kind = integer`, optionally followed by a `#` comment.
    #[error("line {line}: cannot read {text:?} as `kind = weight`")]
    Syntax {
        /// One-based line number.
        line: usize,
        /// The offending line, without its comment.
        text: String,
    },
    /// The key is not an `IssueKind` name.
    #[error("line {line}: unknown rule {name:?}")]
    UnknownKind {
        /// One-based line number.
        line: usize,
        /// The unknown key.
        name: String,
    },
    /// The rule appears twice.
    #[error("line {line}: {kind} is listed twice")]
    Duplicate {
        /// One-based line number of the second occurrence.
        line: usize,
        /// The repeated rule.
        kind: IssueKind,
    },
    /// A rule has no weight.
    #[error("no weight for {0}")]
    Missing(IssueKind),
    /// A weight outside `1..=1000`.
    #[error("{kind}: weight {value} is outside 1..={MAX_WEIGHT}")]
    OutOfRange {
        /// The rule.
        kind: IssueKind,
        /// The value found.
        value: u64,
    },
}

/// The weight of every rule, each in `1..=MAX_WEIGHT`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Weights {
    by_kind: [u32; IssueKind::ALL.len()],
}

impl Weights {
    /// Parse a weights file: one `kind = weight` per line, `#` starts a comment, blank lines are
    /// skipped. Every `IssueKind` must appear exactly once with a weight in `1..=1000`.
    ///
    /// # Errors
    ///
    /// A [`WeightsError`] naming the first problem found.
    pub fn parse(src: &str) -> Result<Weights, WeightsError> {
        let mut by_kind = [0u32; IssueKind::ALL.len()];
        let mut seen = [false; IssueKind::ALL.len()];
        for (n, raw) in src.lines().enumerate() {
            let line = n + 1;
            let code = raw.split('#').next().unwrap_or("").trim();
            if code.is_empty() {
                continue;
            }
            let syntax = || WeightsError::Syntax {
                line,
                text: code.to_owned(),
            };
            let (key, value) = code.split_once('=').ok_or_else(syntax)?;
            let (key, value) = (key.trim(), value.trim());
            if key.is_empty() || value.is_empty() || !value.bytes().all(|b| b.is_ascii_digit()) {
                return Err(syntax());
            }
            let kind = IssueKind::from_name(key).ok_or_else(|| WeightsError::UnknownKind {
                line,
                name: key.to_owned(),
            })?;
            // Digits only, so the sole failure is overflow, which is out of range by any measure.
            let value: u64 = value.parse().unwrap_or(u64::MAX);
            if value == 0 || value > u64::from(MAX_WEIGHT) {
                return Err(WeightsError::OutOfRange { kind, value });
            }
            let i = kind as usize;
            if seen[i] {
                return Err(WeightsError::Duplicate { line, kind });
            }
            seen[i] = true;
            // Checked above: 1..=1000.
            by_kind[i] = value as u32;
        }
        if let Some(i) = seen.iter().position(|s| !s) {
            return Err(WeightsError::Missing(IssueKind::ALL[i]));
        }
        Ok(Weights { by_kind })
    }

    /// The weights compiled into the crate from `weights/devanagari.toml`.
    pub fn builtin() -> &'static Weights {
        static BUILTIN: OnceLock<Weights> = OnceLock::new();
        BUILTIN.get_or_init(|| {
            Weights::parse(WEIGHTS_TOML).expect("weights/devanagari.toml is checked by the tests")
        })
    }

    /// The weight of `kind`.
    pub fn get(&self, kind: IssueKind) -> u32 {
        self.by_kind[kind as usize]
    }

    /// Every weight, keyed by rule, in `IssueKind` declaration order.
    pub fn to_map(&self) -> BTreeMap<IssueKind, u32> {
        IssueKind::ALL.iter().map(|&k| (k, self.get(k))).collect()
    }
}

/// `1_000_000 - floor(penalty * 1000 / cluster_count)`, saturating at 0; `1_000_000` when there
/// are no clusters.
pub fn score_ppm(penalty: u64, cluster_count: usize) -> u32 {
    if cluster_count == 0 {
        return 1_000_000;
    }
    let loss = penalty.saturating_mul(1000) / cluster_count as u64;
    // At most 1_000_000, so the narrowing is exact.
    1_000_000u64.saturating_sub(loss) as u32
}

/// A line ends after a cluster that is exactly LF, CR LF or a bare CR.
fn is_line_terminator(cluster: &Cluster) -> bool {
    matches!(cluster.text.as_str(), "\n" | "\r\n" | "\r")
}

/// The summary, per-line records and score of a validated text.
pub(crate) fn summarise(
    clusters: &[Cluster],
    issues: &[Issue],
    weights: &Weights,
) -> (Summary, Vec<LineSummary>, Score) {
    // Each flagged cluster costs the largest weight among its issues.
    let mut cluster_weight = vec![0u32; clusters.len()];
    let mut by_kind: BTreeMap<IssueKind, usize> = BTreeMap::new();
    for issue in issues {
        let w = weights.get(issue.kind);
        let slot = &mut cluster_weight[issue.cluster];
        *slot = (*slot).max(w);
        *by_kind.entry(issue.kind).or_insert(0) += 1;
    }

    let mut lines = Vec::new();
    let mut penalty = 0u64;
    let mut flagged = 0usize;
    let mut line_penalty = 0u64;
    let mut line_flagged = 0usize;
    let mut line_first = 0usize;
    for (i, cluster) in clusters.iter().enumerate() {
        let w = u64::from(cluster_weight[i]);
        if w > 0 {
            penalty += w;
            flagged += 1;
            line_penalty += w;
            line_flagged += 1;
        }
        let last = i + 1 == clusters.len();
        if is_line_terminator(cluster) || last {
            lines.push(LineSummary {
                index: lines.len(),
                start: clusters[line_first].start,
                end: cluster.end,
                cluster_start: line_first,
                cluster_end: i + 1,
                flagged_clusters: line_flagged,
                score_ppm: score_ppm(line_penalty, i + 1 - line_first),
            });
            line_first = i + 1;
            line_penalty = 0;
            line_flagged = 0;
        }
    }

    let summary = Summary {
        cluster_count: clusters.len(),
        issue_count: issues.len(),
        flagged_clusters: flagged,
        by_kind,
    };
    let score = Score {
        ppm: score_ppm(penalty, clusters.len()),
        penalty,
        weights: weights.to_map(),
    };
    (summary, lines, score)
}
