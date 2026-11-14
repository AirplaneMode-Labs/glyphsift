# Releasing

The release checklist mapped to the definition of done, with what is still Open before a first tag,
is [release.md](release.md); read it first and do not tag while any Blocker-for-tag row there is Open.

Nothing in this repository publishes by itself. Each step below is a deliberate command run by the person
who owns the package names and the registry accounts. The dry runs they rely on are scripts that run
locally; the `packaging` job in `.github/workflows/ci.yml` runs them on Linux on every push and pull
request (configured, not yet run; the job definition is reproduced at the end).

## What is checked before a release

| Check | Command | What it proves |
|---|---|---|
| Rules and tests | `cargo test` | The 147-case table, the fuzz set, the score, the corruption generator, the CLI's exit codes and README, and the committed benchmark CSV and SVG |
| Determinism gate | `scripts/determinism.sh` | Native, Python and WASM reports are byte-identical on 13 golden samples, and the WASM build survives the 20,000-string fuzz set, a 1 MiB input and a 5,000-mark run |
| Benchmark | `cargo run -p glyphsift-cli --release -- bench --verify docs/score-vs-noise.csv` | The committed CSV still satisfies the monotonicity criterion; regenerate it (`bench ... --csv --svg`) when a rule changes and update the README tables |
| npm tarball | `scripts/build-wasm.sh && scripts/package-npm.sh` | The tarball holds only `web/`, `nodejs/`, README, LICENSE, NOTICE and package.json; installs offline into an empty directory from an empty cache with scripts off; `npm ls` shows one package; Node reproduces the CLI report byte for byte (and, with `PLAYWRIGHT_DIR` set, a bundler-free page in Chrome does) |
| Python wheel | `scripts/package-python.sh` | The wheel (stubs, `py.typed`, licences, honest README) installs into a `python3 -m venv` with pip and into a `uv venv`, both offline, a real call returns 750000, and `mypy --strict` accepts the stubs |
| CLI | `. scripts/remap-paths.sh && cargo install --path crates/glyphsift-cli --locked --root <dir>` | The installed binary prints 0.1.0 and exits 0, 1, 2 and 4 as documented |
| Demo | `scripts/build-demo.sh` then `node tests/demo/check_demo.mjs --cli target/release/glyphsift` | The demo built as `pages.yml` builds it, served under `/glyphsift/`, shows the heatmap, reads local files with no request and refuses what it must |
| Manifest tool | `tests/scripts/release-manifest.sh` | `scripts/release-manifest.mjs` writes a valid unsigned manifest, refuses bad dates and output paths, and has no key or signing option |

## Publishing, in order

1. **Version and date.** The workspace version is 0.1.0 (`Cargo.toml`, `[workspace.package]`); the wheel and the
   npm package take it from there. In `CHANGELOG.md` replace `UNRELEASED (release candidate, not tagged)` with the
   date. Commit, tag `v0.1.0`.
2. **crates.io.** `cargo publish -p glyphsift-core`, then (once the index has it) `cargo publish -p glyphsift-cli`.
   `glyphsift-py` and `glyphsift-wasm` are `publish = false`: they ship as a wheel and an npm package. Each crate
   carries `LICENSE` and `NOTICE`.
3. **PyPI.** Wheels for each platform: the `wheels` job in `ci.yml` builds the Linux (`manylinux_2_17` through zig),
   Windows and macOS arm64 wheels and an sdist, and keeps them as a workflow artifact for 7 days (configured, not yet
   run; only the macOS arm64 wheel, tag `macosx_11_0_arm64`, has been built so far, locally). Read that job, change the
   package's OS classifiers to match the wheels that were proven (docs/release.md, row 6), then `twine upload` the
   downloaded files.
   The wheel is abi3: one per platform serves CPython 3.9 and later.
4. **npm.** `npm publish dist/npm/airplanemode-glyphsift-0.1.0.tgz --access public`. The scope `@airplanemode` has
   not been reserved.
5. **Demo.** The `pages` workflow deploys `demo/dist` on every push to `main`.

## Signing the manifest

`scripts/release-manifest.mjs` lists the release artifacts (the wheel and the npm tarball) with their SHA-256
and size in an unsigned `airplanemode.manifest/0.1` (id `glyphsift-release`, licence Apache-2.0, version from
`Cargo.toml`) and writes it inside `dist/`. It cannot sign and never reads a key. `SOURCE_DATE_EPOCH` (decimal
seconds, 0 to 253402300799) fixes `createdAt` for reproducible output.

```sh
SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) node scripts/release-manifest.mjs --out dist/release-manifest.json \
  dist/npm/airplanemode-glyphsift-0.1.0.tgz dist/wheels/glyphsift-0.1.0-*.whl
```

Signing is the owner's step, on the offline key machine, with `cp-sign` from the private `control-plane`
repository (the real key is generated there with `cp-sign keygen`; nothing here ever holds it):

```sh
cargo run -p cp-sign -- sign --key ./keys/key.secret dist/release-manifest.json --out dist/release-manifest.signed.json
cargo run -p cp-sign -- verify --pub ./keys/key.pub dist/release-manifest.signed.json
```

Publish the signed manifest and `key.pub` next to the artifacts. `--allow-test-key` exists for tests only: the
RFC 8032 test key is public, and a manifest signed with it proves the tooling, not a release. On 14 Nov 2026 a dry
run with that key verified and was refused without the flag (`evidence/sprint-3/D3/dry-run-sign.log`); every
output of it stayed outside the repository.

## What a release does not claim

glyphsift 0.1.0 checks structure on synthetic text only: no real document has been scored, the weights are an
author's judgement and were never tuned on the benchmark, and the benchmark proves only that the score falls as
injected structural damage rises. Nothing was measured on an 8 GB Windows no-GPU laptop, and nothing was
signed. A release note should say so in the same words, and the README Limitations section is the list.

## CI job for the packaging dry runs

This is the `packaging` job in `.github/workflows/ci.yml` (actions pinned by SHA there):

```yaml
  packaging:
    name: packaging dry runs (wheel, npm tarball, release manifest)
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: dtolnay/rust-toolchain@683b588c487a69d01f6c6ddf40f036ff682cc2c8 # v1
        with:
          toolchain: "1.98"
          targets: wasm32-unknown-unknown
      - uses: Swatinem/rust-cache@d1527c8f67ef9af357290475d4af4b0fab8f12e0 # v2.9.3
      - uses: actions/setup-python@6d4fd22b20465ccc0f7354476588e8df7c9ca0e0 # v7.1.0
        with:
          python-version: "3.12"
      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
        with:
          node-version: "22"
      - run: python -m pip install uv==0.13.1
      - run: scripts/install-wasm-tools.sh
      - run: scripts/build-wasm.sh
      - run: scripts/package-npm.sh
      - run: scripts/package-python.sh
      - run: tests/scripts/release-manifest.sh
```
