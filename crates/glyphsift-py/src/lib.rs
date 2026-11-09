//! Python bindings. A thin wrapper: all logic lives in `glyphsift-core`; this module only moves
//! strings across the boundary. Import as `glyphsift`.

use pyo3::exceptions::PyValueError;
use pyo3::prelude::*;

/// Validate `text` and return the canonical JSON report (`glyphsift.report/0.2`), byte-identical to
/// the native CLI and the WASM build.
///
/// Raises `ValueError` when the input is over the 4 MiB limit of the core.
#[pyfunction]
fn validate(text: &str) -> PyResult<String> {
    glyphsift_core::validate(text)
        .map(|report| glyphsift_core::to_canonical_json(&report))
        .map_err(|e| PyValueError::new_err(e.to_string()))
}

/// The document score as an integer in parts per million (`1000000` is clean): the `score.ppm` of
/// the report `validate` returns. Raises `ValueError` like `validate`.
#[pyfunction]
fn score_ppm(text: &str) -> PyResult<u32> {
    glyphsift_core::validate(text)
        .map(|report| report.score.ppm)
        .map_err(|e| PyValueError::new_err(e.to_string()))
}

/// The UAX #29 extended grapheme clusters of `text`, as a list of strings.
///
/// Raises `ValueError` over the 4 MiB limit, with the same message as `validate`.
#[pyfunction]
fn clusters(text: &str) -> PyResult<Vec<String>> {
    if text.len() > glyphsift_core::MAX_INPUT_BYTES {
        return Err(PyValueError::new_err(
            glyphsift_core::Error::InputTooLarge {
                bytes: text.len(),
                max: glyphsift_core::MAX_INPUT_BYTES,
            }
            .to_string(),
        ));
    }
    Ok(glyphsift_core::clusters(text)
        .into_iter()
        .map(|c| c.text)
        .collect())
}

#[pymodule]
fn glyphsift(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(validate, m)?)?;
    m.add_function(wrap_pyfunction!(score_ppm, m)?)?;
    m.add_function(wrap_pyfunction!(clusters, m)?)?;
    m.add("__version__", env!("CARGO_PKG_VERSION"))?;
    Ok(())
}
