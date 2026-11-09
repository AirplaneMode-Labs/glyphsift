# Contributing to glyphsift

Thank you for considering a contribution. glyphsift is small and deliberate; these rules keep it so.

## Tests first

Every behaviour change starts with a test. For the validator that means a new `[[case]]` in
`crates/glyphsift-core/tests/cases/devanagari.toml` (input, expected clusters, expected issues with a
one-line `note` saying why), committed before the code that makes it pass. Bug reports that come
with a failing case are the most welcome kind. The same goes for the corruption generator and the
score: a failing test first. Weights live in `crates/glyphsift-core/weights/devanagari.toml`, each line with a
`# source:` comment; they are set from how badly a defect breaks rendering or reading, never tuned on
benchmark output, and a change to the weights file or to `bench/corpus/clean.txt` goes in `CHANGELOG.md` with its reason.

## Determinism

The same input must give byte-identical JSON on native, Python and WASM builds. `clippy.toml`
forbids `HashMap`/`HashSet` and the platform `libm`, the core uses no floating-point type, and it has no
clock, environment or file system access (a test scans `glyphsift-core/src` for `f32`, `f64`, `HashMap` and
`HashSet`). `scripts/determinism.sh` must stay green. Do not add dependencies that bring any of these in.

## Dependencies and licences

Permissive licences only (see `deny.toml`): Apache-2.0, MIT, BSD, ISC, Unicode-3.0, Zlib, MPL-2.0.
Never GPL, LGPL, AGPL or SSPL. A new dependency needs a one-line justification in `CHANGELOG.md`.
`serde_json` must never be built with `preserve_order`.

## Before opening a pull request

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test
cargo check -p glyphsift-core --target wasm32-unknown-unknown
cargo check -p glyphsift-wasm --target wasm32-unknown-unknown
cargo check -p glyphsift-py
scripts/determinism.sh
```

Synthetic inputs only: never paste text from a real document, a customer or a scraped corpus into
tests or docs.

## Style

British spelling, no emojis, commit subjects of at most 72 characters in the imperative mood.
Update `CHANGELOG.md` under `[Unreleased]`.

## Licence

By contributing you agree that your contribution is licensed under the Apache License 2.0, the
licence of this repository, and that you have the right to submit it under that licence.
