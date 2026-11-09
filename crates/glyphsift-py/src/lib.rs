//! Python bindings. A thin wrapper: all logic lives in `glyphsift-core`; this module only moves
//! strings across the boundary. Import as `glyphsift`.

use pyo3::exceptions::PyNotImplementedError;
use pyo3::prelude::*;

/// Validate `text` and return the canonical JSON report (identical bytes to the native CLI and
/// the WASM build).
///
/// Sprint 1: raises `NotImplementedError` naming the sprint the validator lands in.
#[pyfunction]
fn validate(text: &str) -> PyResult<String> {
    match glyphsift_core::validate(text) {
        Ok(report) => Ok(glyphsift_core::to_canonical_json(&report)),
        Err(e @ glyphsift_core::Error::Unimplemented { .. }) => {
            Err(PyNotImplementedError::new_err(e.to_string()))
        }
    }
}

/// The UAX #29 extended grapheme clusters of `text`, as a list of strings.
#[pyfunction]
fn clusters(text: &str) -> Vec<String> {
    glyphsift_core::clusters(text)
        .into_iter()
        .map(|c| c.text)
        .collect()
}

#[pymodule]
fn glyphsift(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(validate, m)?)?;
    m.add_function(wrap_pyfunction!(clusters, m)?)?;
    m.add("__version__", env!("CARGO_PKG_VERSION"))?;
    Ok(())
}
