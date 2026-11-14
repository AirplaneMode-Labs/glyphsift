# @airplanemode/glyphsift

The WebAssembly build of [glyphsift](https://github.com/AirplaneMode-Labs/glyphsift), a deterministic
Devanagari grapheme-cluster validator for extracted Indic text: sixteen structural rules, a document
score from 0 to 1 as an integer in parts per million, per-line scores, no model and no network. The same
canonical JSON report as the Rust CLI and the Python wheel, byte for byte. Part of
[Airplane Mode Labs](https://github.com/AirplaneMode-Labs).

Status: release candidate, not tagged.

## Install

Not published yet: the npm scope @airplanemode and the PyPI and crates.io names are not reserved. The commands below were proven from locally built artifacts on macOS arm64 (an npm pack tarball installed offline into a fresh empty directory, a wheel installed into a fresh venv); publishing to the registries is the owner's step.

The tarball proven here is `airplanemode-glyphsift-0.1.0.tgz`, made by `npm pack` from the wasm-bindgen
output. It has no dependencies, so it installs offline from an empty cache, with install scripts off:

```sh
npm init -y
npm i ./airplanemode-glyphsift-0.1.0.tgz --ignore-scripts --offline --no-audit --no-fund
```

Build the tarball from a clone of the repository (needs `wasm-bindgen` 0.2.129 and `wasm-opt`; see
`scripts/install-wasm-tools.sh`):

```sh
scripts/build-wasm.sh && scripts/package-npm.sh
```

### After the owner publishes

```sh
npm i @airplanemode/glyphsift
```

## Quick start

Node (CommonJS or ES modules; the `nodejs` build loads the WASM synchronously, no `init()`):

```js
const { validate, score_ppm, clusters } = require("@airplanemode/glyphsift");

const report = JSON.parse(validate("नमस्ते।"));   // the canonical report, glyphsift.report/0.2
console.log(report.score.ppm);                      // 1000000 is clean
console.log(score_ppm("कखग\ufffd"));                // 750000: one of four clusters is broken
console.log(JSON.parse(clusters("नमस्ते।")));       // ['न', 'म', 'स्ते', '।']
```

Browser, with no bundler, from an installed directory (the `web` build; call `init()` once, it fetches
`glyphsift_bg.wasm` from next to the module):

```html
<script type="module">
  import init, { validate } from "./node_modules/@airplanemode/glyphsift/web/glyphsift.js";
  await init();
  console.log(JSON.parse(validate("नमस्ते।")).score.ppm);
</script>
```

With a bundler, `import init, { validate } from "@airplanemode/glyphsift"` resolves to the `web` build.
Exports: `validate(text)`, `score_ppm(text)`, `report_spec()`, `clusters(text)`, `clusters_json(text)`
and `issue_kinds()`; all throw an `Error` ("input is too large ...") for input over 4 MiB and never trap.
TypeScript types ship for both builds.

## Limitations

- Release candidate, not tagged, and not published: no registry has this package, and the scope and
  names are not reserved.
- The install was proven only from a locally built tarball on macOS arm64, in Node 22 and in installed
  Chrome. Firefox and Safari were not tested.
- Structural checks only: it judges the order and combination of code points inside one grapheme
  cluster. A well-formed nonsense word, or a visually plausible OCR confusion, scores clean.
- Devanagari only. Text in other scripts is plain text and is never flagged.
- Checked on synthetic text only. No real document has been scored, and the weights are an author's
  judgement, not calibrated.
- Joiners (ZWJ, ZWNJ) in emoji, Persian, Arabic or Latin clusters are not flagged; a joiner that joins
  a space's cluster is not flagged either. Variation selectors on a Devanagari base are not flagged.
- Input over 4 MiB is refused. Speed on an 8 GB Windows no-GPU laptop: not measured.
- The full list, with the benchmark, is in the repository README.

## Security and privacy

No network access, no telemetry, no storage: the module reads only the string it is given. It has no
dependencies and no install scripts. Input is treated as untrusted text and is capped at 4 MiB.

## Licence

Apache-2.0; see `LICENSE` and `NOTICE`.
