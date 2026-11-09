# glyphsift (Python wheel)

Python bindings for [glyphsift](https://github.com/AirplaneMode-Labs/glyphsift), the
deterministic Devanagari grapheme-cluster validator for extracted Indic text. The full
documentation, benchmarks, limitations and security notes live in the repository README.

Package names use the placeholder scope `@airplanemode` / crate names `glyphsift` until the
handles are reserved; nothing is published yet.

## Use

```python
import glyphsift

report_json = glyphsift.validate(text)   # canonical JSON, byte-identical to the CLI and the WASM build
ppm = glyphsift.score_ppm(text)          # integer score in parts per million, 1000000 is clean
glyphsift.clusters(text)                 # UAX #29 extended grapheme clusters, as a list of str
```

`validate`, `score_ppm` and `clusters` raise `ValueError` for input over 4 MiB, with the same message. Limitations: structural checks only,
Devanagari only, nothing published yet; see the repository README.

## Build

From the repository root:

```sh
uvx maturin build --release -m crates/glyphsift-py/Cargo.toml -o target/wheels
```

The wheel is `abi3` (`cp39-abi3`): one wheel per platform for every CPython >= 3.9.

## Licence

Apache-2.0; see `LICENSE` and `NOTICE` in this directory (copies of the repository files).
