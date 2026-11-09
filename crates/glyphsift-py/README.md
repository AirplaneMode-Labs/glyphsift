# glyphsift (Python wheel)

Python bindings for [glyphsift](https://github.com/AirplaneMode-Labs/glyphsift), the
deterministic Devanagari grapheme-cluster validator for extracted Indic text. The full
documentation, benchmarks, limitations and security notes live in the repository README.

Package names use the placeholder scope `@airplanemode` / crate names `glyphsift` until the
handles are reserved; nothing is published yet.

## Status

Skeleton; the validator lands in Sprint 2 (23 Nov to 6 Dec 2026). Today:

- `glyphsift.clusters(text)` returns UAX #29 extended grapheme clusters with byte offsets (real);
- `glyphsift.validate(text)` raises `NotImplementedError` until Sprint 2.

## Build

From the repository root:

```sh
uvx maturin build --release -m crates/glyphsift-py/Cargo.toml -o target/wheels
```

The wheel is `abi3` (`cp39-abi3`): one wheel per platform for every CPython >= 3.9.

## Licence

Apache-2.0; see `LICENSE` and `NOTICE` in this directory (copies of the repository files).
