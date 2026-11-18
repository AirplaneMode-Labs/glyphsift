//! The gate call (Sprint 5, TD-42): one verdict per chunk of extracted text, for a pipeline that ingests
//! text chunk by chunk and must decide, per chunk, whether to keep it, hold it back, or leave it alone.
//!
//! [`gate`] answers with a [`GateReport`]:
//!
//! - **letters** are `char::is_alphabetic()` code points plus every code point in the three Devanagari
//!   blocks (U+0900..U+097F, U+A8E0..U+A8FF, U+1CD0..U+1CFF), so matras, digits and the danda of the main
//!   block count as letters;
//! - `devanagari_ppm` is the integer floor of `block letters * 1_000_000 / letters`;
//! - no letters: script `none`; `devanagari_ppm` under [`GATE_MIN_DEVANAGARI_PPM`] (500,000): script `other`.
//!   Both are `not_scored`: the chunk passes through unjudged and `ppm` is `null`;
//! - otherwise the script is `devanagari`, `ppm` is exactly `validate(text).score.ppm`, and the verdict is
//!   `pass` when `ppm >= threshold_ppm`, `hold` when it is below.
//!
//! The threshold is in parts per million, `0..=1_000_000`; without one, [`DEFAULT_GATE_THRESHOLD_PPM`] is used.
//! `docs/gate.md` derives that default from `docs/score-vs-noise.csv` and says what a hold means for a reader.
//!
//! Same determinism contract as the rest of the core: no floating point, no hash collections, no clock. The
//! JSON ([`gate_to_canonical_json`]) is compact with fields in declaration order, so native, Python and WASM
//! builds emit identical bytes. Input over [`MAX_INPUT_BYTES`] is refused like everywhere else.
//!
//! The score is computed without building the cluster report ([`validate`](crate::validate) allocates a
//! record per cluster), so a gate call on a 4 MiB chunk needs memory proportional to one cluster, not to the
//! input; a test pins the result equal to `validate(text).score.ppm`.

use serde::{Deserialize, Serialize};
use unicode_segmentation::UnicodeSegmentation;

use crate::report::IssueKind;
use crate::score::{Weights, score_ppm};
use crate::{Error, MAX_INPUT_BYTES, rules};

/// Spec discriminator carried by every gate report.
pub const GATE_SPEC: &str = "glyphsift.gate/0.1";

/// The threshold used when the caller gives none, in parts per million. Derived in `docs/gate.md` from
/// `docs/score-vs-noise.csv`: it sits in the gap between the `mixed` family at p=0.1 (lowest seed 982,847) and at
/// p=0.2 (highest seed 970,520). A test re-derives the gap from the committed CSV.
pub const DEFAULT_GATE_THRESHOLD_PPM: u32 = 975_000;

/// A chunk whose Devanagari share of letters is below this (in parts per million) is script `other`.
pub const GATE_MIN_DEVANAGARI_PPM: u32 = 500_000;

/// Highest threshold: a score never exceeds one million parts per million.
pub const GATE_MAX_THRESHOLD_PPM: u32 = 1_000_000;

/// What script the chunk is, for the gate.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GateScript {
    /// At least half of the chunk's letters are in the Devanagari blocks: the chunk is scored.
    Devanagari,
    /// Letters, but under half of them Devanagari: not scored.
    Other,
    /// No letters at all (empty, digits, punctuation, spaces): not scored.
    None,
}

/// The gate's answer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GateVerdict {
    /// Scored, and the score is at or above the threshold.
    Pass,
    /// Scored, and the score is below the threshold: keep the chunk out of the index.
    Hold,
    /// Not scored: the chunk is not Devanagari (or has no letters), so no judgement applies.
    NotScored,
}

/// Everything the gate says about one chunk.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GateReport {
    /// Always [`GATE_SPEC`].
    pub spec: String,
    /// `true` exactly when the script is `devanagari`.
    pub scored: bool,
    /// The script found.
    pub script: GateScript,
    /// Devanagari-block letters over all letters, parts per million, floored. `0` when there are no letters.
    pub devanagari_ppm: u32,
    /// `validate(text).score.ppm` when scored, `null` otherwise.
    pub ppm: Option<u32>,
    /// The threshold that was applied (the default when the caller gave none), also when nothing was scored.
    pub threshold_ppm: u32,
    /// The verdict.
    pub verdict: GateVerdict,
}

/// A code point of the three Devanagari blocks the gate counts: Devanagari, Devanagari Extended, Vedic Extensions.
fn in_devanagari_blocks(c: char) -> bool {
    matches!(u32::from(c), 0x0900..=0x097F | 0xA8E0..=0xA8FF | 0x1CD0..=0x1CFF)
}

/// Check a threshold given as a wide integer (the form the Python and WASM bindings receive).
///
/// # Errors
///
/// [`Error::InvalidThreshold`] outside `0..=1_000_000`.
pub fn parse_threshold(value: i64) -> Result<u32, Error> {
    match u32::try_from(value) {
        Ok(v) if v <= GATE_MAX_THRESHOLD_PPM => Ok(v),
        _ => Err(Error::InvalidThreshold { value }),
    }
}

/// `validate(text).score.ppm`, without the per-cluster records.
fn score_without_report(text: &str) -> u32 {
    let weights = Weights::builtin();
    let mut slots = Vec::new();
    let mut found: Vec<(IssueKind, char)> = Vec::new();
    let mut penalty = 0u64;
    let mut clusters = 0usize;
    for (start, cluster) in text.grapheme_indices(true) {
        clusters += 1;
        rules::check_cluster(cluster, start, &mut slots, &mut found);
        // A flagged cluster costs the largest weight among its issues, as in `score::summarise`.
        let cost = found
            .iter()
            .map(|&(kind, _)| weights.get(kind))
            .max()
            .unwrap_or(0);
        penalty += u64::from(cost);
    }
    score_ppm(penalty, clusters)
}

/// Judge one chunk of text: pass, hold, or not scored (see the module documentation).
///
/// `threshold_ppm` is `None` for [`DEFAULT_GATE_THRESHOLD_PPM`], or a score in `0..=1_000_000`. A threshold of
/// `0` passes every scored chunk, one of `1_000_000` passes only a chunk with no issue at all.
///
/// # Errors
///
/// [`Error::InputTooLarge`] when `text` is longer than [`MAX_INPUT_BYTES`]; [`Error::InvalidThreshold`] when
/// the threshold is above `1_000_000`.
pub fn gate(text: &str, threshold_ppm: Option<u32>) -> Result<GateReport, Error> {
    if text.len() > MAX_INPUT_BYTES {
        return Err(Error::InputTooLarge {
            bytes: text.len(),
            max: MAX_INPUT_BYTES,
        });
    }
    let threshold = parse_threshold(i64::from(
        threshold_ppm.unwrap_or(DEFAULT_GATE_THRESHOLD_PPM),
    ))?;

    let mut letters = 0u64;
    let mut devanagari = 0u64;
    for c in text.chars() {
        if in_devanagari_blocks(c) {
            letters += 1;
            devanagari += 1;
        } else if c.is_alphabetic() {
            letters += 1;
        }
    }
    // At most 1_000_000: the narrowing is exact.
    let devanagari_ppm = (devanagari * 1_000_000).checked_div(letters).unwrap_or(0) as u32;
    let script = if letters == 0 {
        GateScript::None
    } else if devanagari_ppm < GATE_MIN_DEVANAGARI_PPM {
        GateScript::Other
    } else {
        GateScript::Devanagari
    };
    let (ppm, verdict) = if script == GateScript::Devanagari {
        let ppm = score_without_report(text);
        let verdict = if ppm >= threshold {
            GateVerdict::Pass
        } else {
            GateVerdict::Hold
        };
        (Some(ppm), verdict)
    } else {
        (None, GateVerdict::NotScored)
    };
    Ok(GateReport {
        spec: GATE_SPEC.to_owned(),
        scored: script == GateScript::Devanagari,
        script,
        devanagari_ppm,
        ppm,
        threshold_ppm: threshold,
        verdict,
    })
}

/// Canonical JSON for a gate report: compact `serde_json`, fields in declaration order, `ppm` as `null` when
/// nothing was scored.
pub fn gate_to_canonical_json(report: &GateReport) -> String {
    // Serialising a struct of strings, integers, booleans and unit enums cannot fail.
    serde_json::to_string(report).expect("gate report serialisation is infallible")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_are_the_three_documented_ranges() {
        for cp in [0x0900u32, 0x097F, 0xA8E0, 0xA8FF, 0x1CD0, 0x1CFF] {
            assert!(in_devanagari_blocks(char::from_u32(cp).unwrap()), "{cp:#x}");
        }
        for cp in [0x08FF_u32, 0x0980, 0xA8DF, 0xA900, 0x1CCF, 0x1D00, 0x0041] {
            assert!(
                !in_devanagari_blocks(char::from_u32(cp).unwrap()),
                "{cp:#x}"
            );
        }
    }

    #[test]
    fn the_lean_score_equals_the_report_score() {
        for text in [
            "",
            "नमस्ते।",
            "कखग\u{FFFD}",
            "ोम काा ं नमस्ते िदुनिया",
            "क\r\nख\n",
            "क्‍ष",
            "\u{0915}\u{093E}\u{093F}\u{094D}",
            "hello कखग",
        ] {
            assert_eq!(
                score_without_report(text),
                crate::validate(text).unwrap().score.ppm,
                "{text:?}"
            );
        }
    }

    #[test]
    fn the_default_is_a_valid_threshold() {
        assert_eq!(
            parse_threshold(i64::from(DEFAULT_GATE_THRESHOLD_PPM)),
            Ok(DEFAULT_GATE_THRESHOLD_PPM)
        );
        const { assert!(DEFAULT_GATE_THRESHOLD_PPM <= GATE_MAX_THRESHOLD_PPM) };
    }
}
