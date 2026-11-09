//! WASM bindings. A thin wrapper over `glyphsift-core`: it only moves strings across the boundary.
//! Build with `scripts/build-wasm.sh`. No network, no storage, no clock.

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
    // A Vec<String> always serialises.
    serde_json_free_array(&list)
}

/// Crate version, so a page can show which build it loaded.
#[wasm_bindgen]
pub fn version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

/// JSON array of strings without pulling serde_json into the WASM build. Escapes `"`, `\` and
/// U+0000..U+001F exactly as JSON.stringify does.
fn serde_json_free_array(items: &[String]) -> String {
    let mut out = String::from("[");
    for (i, s) in items.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push('"');
        for ch in s.chars() {
            match ch {
                '"' => out.push_str("\\\""),
                '\\' => out.push_str("\\\\"),
                '\u{08}' => out.push_str("\\b"),
                '\t' => out.push_str("\\t"),
                '\n' => out.push_str("\\n"),
                '\u{0C}' => out.push_str("\\f"),
                '\r' => out.push_str("\\r"),
                c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
                c => out.push(c),
            }
        }
        out.push('"');
    }
    out.push(']');
    out
}

#[cfg(test)]
mod tests {
    use super::serde_json_free_array;

    #[test]
    fn escapes_like_json_stringify() {
        let v = vec![
            "a\"b".to_owned(),
            "\\".to_owned(),
            "\u{1}\n".to_owned(),
            "क्ष".to_owned(),
        ];
        assert_eq!(
            serde_json_free_array(&v),
            "[\"a\\\"b\",\"\\\\\",\"\\u0001\\n\",\"क्ष\"]"
        );
        assert_eq!(serde_json_free_array(&[]), "[]");
    }
}
