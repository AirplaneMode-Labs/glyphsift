//! Python bindings. A thin wrapper: all logic lives in `glyphsift-core`; this module only moves
//! strings across the boundary. Import as `glyphsift`.

use pyo3::exceptions::{PyOverflowError, PyTypeError, PyValueError};
use pyo3::prelude::*;
use pyo3::types::PyBool;

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

/// Judge one chunk of text and return the canonical `glyphsift.gate/0.1` JSON, byte-identical to
/// `glyphsift gate` and the WASM build: `pass`, `hold`, or `not_scored` (text that is not mostly Devanagari
/// is passed through unjudged). `threshold_ppm` is an `int` in 0..=1000000, or `None` for
/// `DEFAULT_GATE_THRESHOLD_PPM`.
///
/// Raises `ValueError` for input over 4 MiB, for a threshold outside 0..=1000000 and for a string with an
/// unpaired surrogate (PyO3 cannot turn one into text: `UnicodeEncodeError` is a `ValueError`), and
/// `TypeError` for a threshold that is not an `int` (a `bool` or a `float` is refused too).
#[pyfunction]
#[pyo3(signature = (text, threshold_ppm=None))]
fn gate(text: &str, threshold_ppm: Option<&Bound<'_, PyAny>>) -> PyResult<String> {
    let threshold = threshold_arg(threshold_ppm)?;
    glyphsift_core::gate(text, threshold)
        .map(|report| glyphsift_core::gate_to_canonical_json(&report))
        .map_err(|e| PyValueError::new_err(e.to_string()))
}

/// The gate threshold argument: `None` (or a Python `None`) is the default; an `int` must be 0..=1000000.
fn threshold_arg(value: Option<&Bound<'_, PyAny>>) -> PyResult<Option<u32>> {
    let Some(value) = value else {
        return Ok(None);
    };
    if value.is_none() {
        return Ok(None);
    }
    // `bool` is an `int` in Python, and `True` is not a threshold.
    if value.is_instance_of::<PyBool>() {
        return Err(PyTypeError::new_err(
            "threshold_ppm must be an int or None, not a bool",
        ));
    }
    match value.extract::<i64>() {
        Ok(n) => glyphsift_core::parse_threshold(n)
            .map(Some)
            .map_err(|e| PyValueError::new_err(e.to_string())),
        // An int too large for 64 bits is out of range, not a type error.
        Err(e) if e.is_instance_of::<PyOverflowError>(value.py()) => Err(PyValueError::new_err(
            "threshold is outside 0..=1000000 ppm",
        )),
        Err(e) => Err(e),
    }
}

#[pymodule]
fn glyphsift(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(validate, m)?)?;
    m.add_function(wrap_pyfunction!(score_ppm, m)?)?;
    m.add_function(wrap_pyfunction!(clusters, m)?)?;
    m.add_function(wrap_pyfunction!(gate, m)?)?;
    m.add("GATE_SPEC", glyphsift_core::GATE_SPEC)?;
    m.add(
        "DEFAULT_GATE_THRESHOLD_PPM",
        glyphsift_core::DEFAULT_GATE_THRESHOLD_PPM,
    )?;
    m.add("__version__", env!("CARGO_PKG_VERSION"))?;
    Ok(())
}
