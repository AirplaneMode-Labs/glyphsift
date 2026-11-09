//! WASM bindings. A thin wrapper over `glyphsift-core`: it only moves strings across the boundary.
//! Build with `scripts/build-wasm.sh`. No network, no storage, no clock.
//!
//! Every function returns a JSON string (or throws), so the page needs no generated TypeScript
//! types and the bytes stay identical to the native build's `serde_json` output.

use wasm_bindgen::prelude::*;

/// Validate `text` and return the canonical JSON report; identical bytes to the native and Python
/// builds. Throws an `Error` whose message names the sprint while the validator is unimplemented.
#[wasm_bindgen]
pub fn validate(text: &str) -> Result<String, JsError> {
    glyphsift_core::validate(text)
        .map(|r| glyphsift_core::to_canonical_json(&r))
        .map_err(|e| JsError::new(&e.to_string()))
}

/// The UAX #29 extended grapheme clusters of `text`, as a JSON array of strings.
#[wasm_bindgen]
pub fn clusters(text: &str) -> String {
    let list: Vec<String> = glyphsift_core::clusters(text)
        .into_iter()
        .map(|c| c.text)
        .collect();
    to_json(&list)
}

/// The UAX #29 extended grapheme clusters of `text` with byte offsets and code points: a JSON
/// array of `{index, text, start, end, code_points}` objects, the same `Cluster` records a report
/// carries.
#[wasm_bindgen]
pub fn clusters_json(text: &str) -> String {
    to_json(&glyphsift_core::clusters(text))
}

/// The wire names of every rule the validator reports, in declaration order, as a JSON array of
/// strings (sixteen in 0.1).
#[wasm_bindgen]
pub fn issue_kinds() -> String {
    let names: Vec<&'static str> = glyphsift_core::IssueKind::ALL
        .iter()
        .map(|k| k.name())
        .collect();
    to_json(&names)
}

/// The report spec discriminator every report carries (`glyphsift.report/0.1`).
#[wasm_bindgen]
pub fn report_spec() -> String {
    glyphsift_core::REPORT_SPEC.to_owned()
}

/// Crate version, so a page can show which build it loaded.
#[wasm_bindgen]
pub fn version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
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
            clusters("a\"b\\\u{1}\nक्ष"),
            "[\"a\",\"\\\"\",\"b\",\"\\\\\",\"\\u0001\",\"\\n\",\"क्ष\"]"
        );
        assert_eq!(clusters(""), "[]");
    }

    #[test]
    fn clusters_json_carries_offsets_and_code_points() {
        let v: serde_json::Value = serde_json::from_str(&clusters_json("नमस्ते।")).unwrap();
        let rows = v.as_array().unwrap();
        assert_eq!(rows.len(), 4);
        assert_eq!(rows[2]["text"], "स्ते");
        assert_eq!(rows[2]["start"], 6);
        assert_eq!(rows[2]["end"], 18);
        assert_eq!(
            rows[2]["code_points"],
            serde_json::json!(["U+0938", "U+094D", "U+0924", "U+0947"])
        );
        assert_eq!(clusters_json(""), "[]");
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
    fn report_spec_and_version_match_the_core() {
        assert_eq!(report_spec(), glyphsift_core::REPORT_SPEC);
        assert_eq!(version(), "0.1.0");
    }

    #[test]
    fn validate_is_unimplemented_and_names_the_sprint() {
        // JsError only converts to a JsValue on wasm32; on native, check the core message that the
        // binding forwards verbatim.
        let msg = glyphsift_core::validate("x").unwrap_err().to_string();
        assert!(msg.contains("Sprint 2"));
    }
}
