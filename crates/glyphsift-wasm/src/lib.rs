//! WASM bindings. A thin wrapper over `glyphsift-core`: it only moves strings across the boundary.
//! Build with `scripts/build-wasm.sh`. No network, no storage, no clock.
//!
//! Every function returns a JSON string or an integer (or throws), so the page needs no generated TypeScript
//! types and the bytes stay identical to the native build's `serde_json` output.
//!
//! `gate` (Sprint 5) takes the text as a JavaScript value and checks it itself: wasm-bindgen turns an
//! unpaired surrogate in a `&str` argument into U+FFFD without a word, so the gate would answer for text the
//! caller never had. It asks the engine's `String.prototype.isWellFormed` first and throws a `TypeError`
//! before the core is called.

use wasm_bindgen::prelude::*;

/// Validate `text` and return the canonical JSON report (`glyphsift.report/0.2`): identical bytes
/// to the native CLI and the Python build. Throws an `Error` when the input is over the 4 MiB
/// limit of the core; it never traps on any input.
#[wasm_bindgen]
pub fn validate(text: &str) -> Result<String, JsError> {
    glyphsift_core::validate(text)
        .map(|r| glyphsift_core::to_canonical_json(&r))
        .map_err(|e| JsError::new(&e.to_string()))
}

/// The document score of `text` as an integer in parts per million (`1000000` is clean), the
/// `score.ppm` of [`validate`]'s report. Throws like [`validate`].
#[wasm_bindgen]
pub fn score_ppm(text: &str) -> Result<u32, JsError> {
    glyphsift_core::validate(text)
        .map(|r| r.score.ppm)
        .map_err(|e| JsError::new(&e.to_string()))
}

/// The UAX #29 extended grapheme clusters of `text`, as a JSON array of strings. Throws the same
/// "too large" error as [`validate`] for input over the 4 MiB limit; it never traps.
#[wasm_bindgen]
pub fn clusters(text: &str) -> Result<String, JsError> {
    check_len(text).map_err(|e| JsError::new(&e))?;
    let list: Vec<String> = glyphsift_core::clusters(text)
        .into_iter()
        .map(|c| c.text)
        .collect();
    Ok(to_json(&list))
}

/// The UAX #29 extended grapheme clusters of `text` with byte offsets and code points: a JSON
/// array of `{index, text, start, end, code_points}` objects, the same `Cluster` records a report
/// carries. Throws like [`clusters`].
#[wasm_bindgen]
pub fn clusters_json(text: &str) -> Result<String, JsError> {
    check_len(text).map_err(|e| JsError::new(&e))?;
    Ok(to_json(&glyphsift_core::clusters(text)))
}

#[wasm_bindgen]
extern "C" {
    /// A JavaScript `TypeError`: the right error for an argument of the wrong kind or an ill-formed string.
    type TypeError;
    #[wasm_bindgen(constructor)]
    fn new(message: &str) -> TypeError;
}

#[wasm_bindgen]
extern "C" {
    /// A JavaScript `RangeError`: the right error for a whole number outside the allowed range.
    type RangeError;
    #[wasm_bindgen(constructor)]
    fn new(message: &str) -> RangeError;
}

#[wasm_bindgen]
extern "C" {
    /// A string value, seen only to call `String.prototype.isWellFormed` on it.
    type StringProbe;
    /// `true` when the string has no unpaired surrogate. `catch` turns a missing method (an engine older
    /// than Chrome 111 or Node 20) into an `Err`, which the gate treats as a refusal rather than guessing.
    #[wasm_bindgen(method, catch, js_name = isWellFormed)]
    fn is_well_formed(this: &StringProbe) -> Result<bool, JsValue>;
}

fn type_error(message: &str) -> JsValue {
    JsValue::from(TypeError::new(message))
}

/// What is wrong with a gate threshold given as a JavaScript number.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ThresholdProblem {
    /// NaN, an infinity, or a number with a fractional part.
    NotWhole,
    /// A whole number outside 0..=1,000,000.
    OutOfRange,
}

/// A gate threshold from a JavaScript number: a whole number in `0..=1_000_000`.
fn threshold_from_number(f: f64) -> Result<u32, ThresholdProblem> {
    if !f.is_finite() {
        return Err(ThresholdProblem::NotWhole);
    }
    // From 2^53 up every double is a whole number, and none is in range.
    if f >= 9_007_199_254_740_992.0 || f <= -9_007_199_254_740_992.0 {
        return Err(ThresholdProblem::OutOfRange);
    }
    // |f| < 2^53 here, so the cast to i64 is exact for a whole number and loses the fraction otherwise.
    let n = f as i64;
    if n as f64 != f {
        return Err(ThresholdProblem::NotWhole);
    }
    glyphsift_core::parse_threshold(n).map_err(|_| ThresholdProblem::OutOfRange)
}

/// Judge one chunk of text and return the canonical `glyphsift.gate/0.1` JSON (`docs/gate.md`): `pass`,
/// `hold`, or `not_scored` (text that is not mostly Devanagari is passed through unjudged, `ppm` null).
/// Identical bytes to `glyphsift gate` and the Python wheel.
///
/// `threshold_ppm` is a whole number from 0 to 1000000; `undefined` or `null` means the default,
/// `default_gate_threshold_ppm()` (975000).
///
/// Throws a `TypeError` when `text` is not a string or is not well-formed (an unpaired surrogate), or when
/// the threshold is not a whole number; a `RangeError` for a whole number outside 0..=1000000; an `Error`
/// saying "too large" for input over 4 MiB. It never traps.
#[wasm_bindgen]
pub fn gate(
    #[wasm_bindgen(unchecked_param_type = "string")] text: &JsValue,
    #[wasm_bindgen(unchecked_optional_param_type = "number")] threshold_ppm: Option<JsValue>,
) -> Result<String, JsValue> {
    if !text.is_string() {
        return Err(type_error("gate: text must be a string"));
    }
    match text.unchecked_ref::<StringProbe>().is_well_formed() {
        Ok(true) => {}
        Ok(false) => {
            return Err(type_error(
                "gate: the text is not well-formed Unicode: it contains an unpaired surrogate",
            ));
        }
        Err(_) => {
            return Err(type_error(
                "gate: this JavaScript engine has no String.prototype.isWellFormed, so the text cannot be checked for unpaired surrogates",
            ));
        }
    }
    // A string value is always convertible, and it is well-formed, so nothing was replaced.
    let Some(text) = text.as_string() else {
        return Err(type_error("gate: text must be a string"));
    };
    let threshold = match threshold_ppm.as_ref() {
        None => None,
        Some(v) if v.is_null() || v.is_undefined() => None,
        Some(v) => match v.as_f64() {
            None => return Err(type_error("gate: threshold_ppm must be a number")),
            Some(f) => match threshold_from_number(f) {
                Ok(n) => Some(n),
                Err(ThresholdProblem::NotWhole) => {
                    return Err(type_error("gate: threshold_ppm must be a whole number"));
                }
                Err(ThresholdProblem::OutOfRange) => {
                    return Err(JsValue::from(RangeError::new(
                        "gate: threshold_ppm must be from 0 to 1000000",
                    )));
                }
            },
        },
    };
    glyphsift_core::gate(&text, threshold)
        .map(|r| glyphsift_core::gate_to_canonical_json(&r))
        .map_err(|e| JsValue::from(JsError::new(&e.to_string())))
}

/// The gate spec discriminator every gate result carries (`glyphsift.gate/0.1`).
#[wasm_bindgen]
pub fn gate_spec() -> String {
    glyphsift_core::GATE_SPEC.to_owned()
}

/// The threshold `gate` uses when none is given: 975000 parts per million (derived in `docs/gate.md`).
#[wasm_bindgen]
pub fn default_gate_threshold_ppm() -> u32 {
    glyphsift_core::DEFAULT_GATE_THRESHOLD_PPM
}

/// The input-size guard shared by every export that walks the whole text. The message is the one
/// `validate` raises, so callers see one "too large" error everywhere.
fn check_len(text: &str) -> Result<(), String> {
    if text.len() > glyphsift_core::MAX_INPUT_BYTES {
        return Err(glyphsift_core::Error::InputTooLarge {
            bytes: text.len(),
            max: glyphsift_core::MAX_INPUT_BYTES,
        }
        .to_string());
    }
    Ok(())
}

/// The wire names of every rule the validator reports, in declaration order, as a JSON array of
/// strings (sixteen).
#[wasm_bindgen]
pub fn issue_kinds() -> String {
    let names: Vec<&'static str> = glyphsift_core::IssueKind::ALL
        .iter()
        .map(|k| k.name())
        .collect();
    to_json(&names)
}

/// The report spec discriminator every report carries (`glyphsift.report/0.2`).
#[wasm_bindgen]
pub fn report_spec() -> String {
    glyphsift_core::REPORT_SPEC.to_owned()
}

/// Compact JSON. Strings, integers and vectors of them cannot fail to serialise.
fn to_json<T: serde::Serialize>(value: &T) -> String {
    serde_json::to_string(value).expect("strings and integers always serialise")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clusters_escape_like_json_stringify() {
        assert_eq!(
            clusters("a\"b\\\u{1}\nक्ष").ok().as_deref(),
            Some("[\"a\",\"\\\"\",\"b\",\"\\\\\",\"\\u0001\",\"\\n\",\"क्ष\"]")
        );
        assert_eq!(clusters("").ok().as_deref(), Some("[]"));
    }

    #[test]
    fn clusters_json_carries_offsets_and_code_points() {
        let v: serde_json::Value =
            serde_json::from_str(&clusters_json("नमस्ते।").ok().unwrap()).unwrap();
        let rows = v.as_array().unwrap();
        assert_eq!(rows.len(), 4);
        assert_eq!(rows[2]["text"], "स्ते");
        assert_eq!(rows[2]["start"], 6);
        assert_eq!(rows[2]["end"], 18);
        assert_eq!(
            rows[2]["code_points"],
            serde_json::json!(["U+0938", "U+094D", "U+0924", "U+0947"])
        );
        assert_eq!(clusters_json("").ok().as_deref(), Some("[]"));
    }

    // JsError is not Debug and cannot be built off wasm32, so the over-limit refusal is checked
    // through the shared guard the exports call.
    #[test]
    fn clusters_refuse_input_over_the_core_limit() {
        assert!(check_len("a").is_ok());
        let at = "a".repeat(glyphsift_core::MAX_INPUT_BYTES);
        assert!(check_len(&at).is_ok());
        let over = "a".repeat(glyphsift_core::MAX_INPUT_BYTES + 1);
        assert!(check_len(&over).is_err());
        let eight = "a".repeat(8 * 1024 * 1024);
        assert!(check_len(&eight).is_err());
    }

    #[test]
    fn gate_thresholds_are_whole_numbers_from_0_to_1000000() {
        for (f, want) in [
            (0.0, Ok(0)),
            (-0.0, Ok(0)),
            (975_000.0, Ok(975_000)),
            (1_000_000.0, Ok(1_000_000)),
            (1_000_001.0, Err(ThresholdProblem::OutOfRange)),
            (-1.0, Err(ThresholdProblem::OutOfRange)),
            (4_294_967_296.0, Err(ThresholdProblem::OutOfRange)),
            (9_007_199_254_740_992.0, Err(ThresholdProblem::OutOfRange)),
            (1e21, Err(ThresholdProblem::OutOfRange)),
            (-1e21, Err(ThresholdProblem::OutOfRange)),
            (1.5, Err(ThresholdProblem::NotWhole)),
            (0.1, Err(ThresholdProblem::NotWhole)),
            (-0.5, Err(ThresholdProblem::NotWhole)),
            (f64::NAN, Err(ThresholdProblem::NotWhole)),
            (f64::INFINITY, Err(ThresholdProblem::NotWhole)),
            (f64::NEG_INFINITY, Err(ThresholdProblem::NotWhole)),
        ] {
            assert_eq!(threshold_from_number(f), want, "{f}");
        }
    }

    #[test]
    fn gate_spec_and_default_match_the_core() {
        assert_eq!(gate_spec(), "glyphsift.gate/0.1");
        assert_eq!(gate_spec(), glyphsift_core::GATE_SPEC);
        assert_eq!(default_gate_threshold_ppm(), 975_000);
    }

    #[test]
    fn issue_kinds_are_sixteen_distinct_names() {
        let mut names: Vec<String> = serde_json::from_str(&issue_kinds()).unwrap();
        assert_eq!(names.len(), 16);
        assert_eq!(names[0], "dependent_vowel_without_base");
        names.sort_unstable();
        names.dedup();
        assert_eq!(names.len(), 16);
    }

    #[test]
    fn report_spec_is_0_2_and_matches_the_core() {
        assert_eq!(report_spec(), "glyphsift.report/0.2");
        assert_eq!(report_spec(), glyphsift_core::REPORT_SPEC);
    }

    // JsError is not Debug, so `.expect()` cannot be called on the Result directly.
    #[allow(clippy::ok_expect)]
    #[test]
    fn validate_returns_the_canonical_report_json_of_the_core() {
        for text in ["", "नमस्ते।", "ोम काा ं नमस्ते िदुनिया", "क\r\nख\n", "\u{FFFD}"]
        {
            let want = glyphsift_core::to_canonical_json(&glyphsift_core::validate(text).unwrap());
            // The Ok path never builds a JsError, so it runs on native targets.
            let got = validate(text).ok().expect("validates");
            assert_eq!(got, want, "{text:?}");
        }
    }

    #[test]
    fn score_ppm_matches_the_report() {
        assert_eq!(score_ppm("नमस्ते।").ok(), Some(1_000_000));
        assert_eq!(score_ppm("").ok(), Some(1_000_000));
        assert_eq!(score_ppm("कखग\u{FFFD}").ok(), Some(750_000));
    }
}
