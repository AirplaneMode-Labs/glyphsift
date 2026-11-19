# glyphsift (Python wheel)

Python bindings for [glyphsift](https://github.com/AirplaneMode-Labs/glyphsift), the deterministic
Devanagari grapheme-cluster validator for extracted Indic text: sixteen structural rules, a document
score from 0 to 1 as an integer in parts per million, no model and no network. Part of
[Airplane Mode Labs](https://github.com/AirplaneMode-Labs).

Status: 0.1.2, release candidate, not tagged.

## Install

Not published yet: the npm scope @airplanemode and the PyPI and crates.io names are not reserved. The commands below were proven from locally built artifacts on macOS arm64 (an npm pack tarball installed offline into a fresh empty directory, a wheel installed into a fresh venv); publishing to the registries is the owner's step.

The wheel proven here is `glyphsift-0.1.2-cp39-abi3-macosx_11_0_arm64.whl`: platform tag
`macosx_11_0_arm64` (macOS on Apple silicon), `abi3`, so one wheel serves every CPython 3.9 or later on
that platform. Linux and Windows wheels were built by CI at commit 5ff0c47 (run 43667702791, read on
18 Nov 2026: a `manylinux_2_17` wheel through zig, a `win_amd64` wheel, and an sdist, each wheel installed into a fresh
venv with `--no-index` and answering `ppm 1000000`). Those are workflow artifacts kept for 7 days, not releases:
nothing from that job is published, and the 0.1.2 wheels have not been built by CI yet (the owner's push does that).

Install the locally built wheel into a fresh environment, offline (both ways were run):

```sh
python3 -m venv venv && venv/bin/pip install --no-index --no-deps glyphsift-0.1.2-cp39-abi3-macosx_11_0_arm64.whl
uv venv uvenv && uv pip install --offline --no-index --no-deps --python uvenv/bin/python glyphsift-0.1.2-cp39-abi3-macosx_11_0_arm64.whl
```

Build the wheel from a clone of the repository:

```sh
. scripts/remap-paths.sh && uvx maturin@1.16.0 build --release -m crates/glyphsift-py/Cargo.toml -o target/wheels
```

### After the owner publishes

```sh
pip install glyphsift
```

## Quick start

```python
import json
import glyphsift

report = json.loads(glyphsift.validate("नमस्ते।"))   # canonical JSON: the same bytes as `glyphsift check` and the WASM build
print(report["score"]["ppm"])                         # 1000000 is clean
print(glyphsift.score_ppm("कखग\ufffd"))               # 750000: one of four clusters is broken
print(glyphsift.clusters("नमस्ते।"))                  # ['न', 'म', 'स्ते', '।']

# The gate (Sprint 5): one verdict per chunk of extracted text.
verdict = json.loads(glyphsift.gate("कखग\ufffd"))   # a damaged Devanagari chunk
print(verdict["verdict"], verdict["ppm"])             # hold 750000 (default threshold 975000)
print(json.loads(glyphsift.gate("hello"))["verdict"]) # not_scored: not Devanagari, passed through unjudged
print(json.loads(glyphsift.gate("कखग\ufffd", 750000))["verdict"])   # pass: the score equals the threshold
```

`validate`, `score_ppm`, `clusters` and `gate` raise `ValueError` ("input is too large ...") for input over
4 MiB. The package ships type stubs (`glyphsift.pyi` and `py.typed`), so `mypy --strict` and editors
see `validate(text: str) -> str`, `score_ppm(text: str) -> int`, `clusters(text: str) -> list[str]` and
`gate(text: str, threshold_ppm: int | None = None) -> str`.

`glyphsift.gate(text, threshold_ppm=None)` returns the canonical `glyphsift.gate/0.1` JSON: `pass`, `hold` (a Devanagari
chunk scoring below the threshold) or `not_scored` (text that is not mostly Devanagari is passed through unjudged, `ppm`
null). `glyphsift.DEFAULT_GATE_THRESHOLD_PPM` is 975000. A threshold outside 0..1000000 raises `ValueError`, a
non-integer one `TypeError`, and a string with an unpaired surrogate `ValueError`. The rules and the derivation of the
default are in the repository's `docs/gate.md`.

## Limitations

- Release candidate, not tagged, and not published: no registry has this package.
- Only a macOS arm64 wheel was installed from a local build (tag `macosx_11_0_arm64`). CI built a `manylinux_2_17` wheel, a
  `win_amd64` wheel and an sdist at 5ff0c47 (run 43667702791) and installed each wheel; they were not installed anywhere else
  and nothing is published. The wheel's OS classifier stays "MacOS" until the owner publishes CI-built wheels.
- The gate is structural and Devanagari-only: `not_scored` for any other script, and no claim about Hindi answer quality.
- Structural checks only: it judges the order and combination of code points inside one grapheme
  cluster. A well-formed nonsense word, or a visually plausible OCR confusion, scores clean.
- Devanagari only. Text in other scripts is plain text and is never flagged.
- Checked on synthetic text only. No real document has been scored, and the weights are an author's
  judgement, not calibrated.
- Joiners (ZWJ, ZWNJ) in emoji, Persian, Arabic or Latin clusters are not flagged; a joiner that joins
  a space's cluster is not flagged either. Variation selectors on a Devanagari base are not flagged.
- Input over 4 MiB is refused. No benchmark exists on an 8 GB Windows no-GPU laptop (not measured).
- The full list, with the benchmark, is in the repository README.

## Security and privacy

No network access and no telemetry; the extension reads only the string it is given and holds no state
between calls. Input is treated as untrusted text and is capped at 4 MiB.

## Licence

Apache-2.0; see `LICENSE` and `NOTICE` (copies of the repository files).
