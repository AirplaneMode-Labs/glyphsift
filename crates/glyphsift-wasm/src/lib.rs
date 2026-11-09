//! WASM bindings. A thin wrapper over `glyphsift-core`: it only moves strings across the boundary.
//! Build with `scripts/build-wasm.sh`. No network, no storage, no clock.
//!
//! Every function returns a JSON string or an integer (or throws), so the page needs no generated TypeScript
//! types and the bytes stay identical to the native build's `serde_json` output.

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
