# Benchmarks: raw results

Nothing here is measured on an 8 GB laptop unless a file says so, and no file does yet: every `Apple M5 Pro, 48 GB` result is the development Mac's, not the target's, and the `GitHub-hosted CI runners` file is a CI record.

Owner decision, 20 Nov 2026: every benchmark glyphsift quotes is committed here as a raw file that records when it was run (UTC), on which commit, on which machine (CPU model and RAM only) and by which command. The README's
[Benchmarks](../../README.md#benchmarks) section, [docs/gate.md](../gate.md) and [docs/what-glyphsift-measures.md](../what-glyphsift-measures.md) quote figures from these files, and the demo footer links this folder.
A figure quoted anywhere without a matching row in a file here is a failing test, or carries the words "raw data not kept" (see the end of this page).

## The files

| File | What it is | Date (UTC) | Commit | Machine |
|---|---|---|---|---|
| `score-vs-noise.csv` | The 420 rows of `glyphsift bench` (score, flagged clusters and recall for each noise family, noise level and seed on the 288-line synthetic corpus). A byte-identical copy of [docs/score-vs-noise.csv](../score-vs-noise.csv), which the tests, the chart and the source package read where it is | 2026-11-20 | `3c0bb4d` | Apple M5 Pro, 48 GB |
| `score-vs-noise.provenance.json` | The record for that CSV: SHA-256 of the CSV and the SVG, three fresh `bench` runs that were byte-identical to them, `bench --verify` printing `verdict: PASS`, and the wall-clock time of each run | 2026-11-20 | `3c0bb4d` | Apple M5 Pro, 48 GB |
| `gate-holds.json` | How many noised chunks the gate holds: five noise families at three lines per chunk, and the `mixed` family at one, three and eight lines (the two tables of [docs/gate.md](../gate.md), and "285 of 288" in the README) | 2026-11-20 | `3c0bb4d` | Apple M5 Pro, 48 GB |
| `joiner-sites.json` | Injected joiners at p=0.05, seeds 1 to 3: 807 sites, 599 of them in a Devanagari-based cluster where the rule is expected to fire (the README's "599 of 807") | 2026-11-20 | `3c0bb4d` | Apple M5 Pro, 48 GB |
| `throughput-m5pro-48gb.json` | Time to check, score and gate a 1 MiB synthetic text: native `glyphsift check` and `gate`, WASM `validate()`, `score_ppm()` and `gate()` in Node 22; all five runs of each | 2026-11-20 | `3c0bb4d` | Apple M5 Pro, 48 GB |
| `demo-1mib-m5pro-48gb.json` | Time for the demo in headless Chrome to validate and render exactly 1 MiB pasted into the page (one run) | 2026-11-20 | `3c0bb4d` | Apple M5 Pro, 48 GB |
| `wasm-linearity-m5pro-48gb.json` | WASM `validate()` on a 5,000-mark cluster against a 2,500-mark one: the ratio (1.99; linear is 2, quadratic 4) | 2026-11-20 | `3c0bb4d` | Apple M5 Pro, 48 GB |
| `ci-run-43667702791.json` | The sizes of the files CI run 43667702791 built (0.1.0 wheels, sdist, npm tarball) and of its workflow artifacts, copied from that run's logs and artifact list; the lasting record, because the artifacts expire on 22 Nov 2026 ([docs/release.md](../release.md), "First CI run of the wheels job") | 2026-11-15 | `5ff0c47` | GitHub-hosted CI runners (ubuntu-latest, windows-latest, macos-latest) |

Every `.json` file has the same envelope: `schema` (`glyphsift.benchmark/1`), `benchmark`, `date`, `commit` (40 hex digits, the commit the code under test was built from), `build_inputs_modified` (must be `false`: `crates/`, `Cargo.toml`,
`Cargo.lock` and `rust-toolchain.toml` are those of the commit), `worktree_clean`, `machine`, `environment` (operating system, Node, rustc, Chrome and the glyphsift version, as they apply), `method`, `command` and `data`.
`worktree_clean: false` means files outside the build inputs (scripts, tests, docs) had uncommitted changes while the benchmark ran; the measured code is the commit's. No file is over 5 MB.

## Reproduce

Build what the commands need once, from the root of a clone (Rust 1.98 with the wasm32 target, `wasm-bindgen` 0.2.129 and `wasm-opt`: `scripts/install-wasm-tools.sh`; Node 22):

```sh
cargo build --release --locked -p glyphsift-cli
scripts/build-wasm.sh
scripts/build-demo.sh                                  # only for the demo file
npm ci --prefix tools/playwright --ignore-scripts      # only for the demo file; uses the installed Google Chrome
```

The 1 MiB text (the corpus repeated line by line up to 1,048,576 bytes: 12,888 lines, 1,048,569 bytes, SHA-256 `3336ba4c6d3fef2e776a2b19905571215e6494bc6819af6de3e032aed0a517b7`):

```sh
node -e 'const fs=require("fs");const L=fs.readFileSync("bench/corpus/clean.txt","utf8").split("\n").filter((x,i,a)=>!(i===a.length-1&&x===""));let out="",bytes=0,i=0;for(;;){const l=L[i%L.length]+"\n";const n=Buffer.byteLength(l);if(bytes+n>1048576)break;out+=l;bytes+=n;i++}fs.writeFileSync("corpus-1mib.txt",out);console.log(i,"lines",bytes,"bytes")'
```

The command in each file's `command` field, exactly as recorded:

```sh
node scripts/throughput.mjs corpus-1mib.txt --cli target/release/glyphsift --json docs/benchmarks/throughput-m5pro-48gb.json
PLAYWRIGHT_DIR=$PWD/tools/playwright node tests/demo/check_demo.mjs --cli target/release/glyphsift --bench-json docs/benchmarks/demo-1mib-m5pro-48gb.json
node tests/wasm/run_wasm_safety.mjs --bench-json docs/benchmarks/wasm-linearity-m5pro-48gb.json
target/release/glyphsift bench --corpus bench/corpus/clean.txt --seeds 1,2,3 --csv docs/score-vs-noise.csv --svg docs/score-vs-noise.svg
target/release/glyphsift corrupt --family joiner_inject --p 0.05 --seed <1|2|3> --sites <file> < bench/corpus/clean.txt > /dev/null
cargo test --locked -p glyphsift-core --features corrupt --test gate_noise the_doc_tables_are_these_exact_hold_counts -- --nocapture
gh api repos/AirplaneMode-Labs/glyphsift/actions/runs/43667702791 ; gh api repos/AirplaneMode-Labs/glyphsift/actions/runs/43667702791/artifacts ; gh run view 43667702791 --repo AirplaneMode-Labs/glyphsift --job <job_id> --log   (job ids are in data.jobs)
```

The first three write their file themselves (`--json`, `--bench-json`; add `--machine "<CPU model>, <N> GB"` for a machine Node cannot name, and run them on that machine). The next three are recorded by
`node scripts/record-benchmarks.mjs score-vs-noise`, `node scripts/record-benchmarks.mjs joiner-sites` and `node scripts/record-benchmarks.mjs gate-holds` (they re-run the command, check the result against the committed files and write the
files above; the first two need the release binary, the third needs `cargo`). The last line is the `gh` read-only calls that the CI file was made from: its numbers are the `ls -l`, `packed ... (N bytes)` and `Final size is N bytes` lines of the job
logs and the `size_in_bytes` of the artifact list.

The scores, the hold counts and the joiner counts are deterministic integers: another machine must reproduce them byte for byte (`glyphsift bench --verify docs/score-vs-noise.csv` re-checks the CSV without regenerating). The timings are not:
another machine, or this one on another day, gives other milliseconds, and a re-run replaces the file with its own date, commit and machine.

To add the 8 GB laptop (the owner's step, [docs/release.md](../release.md), row 2): run the first three commands on that laptop with `--json docs/benchmarks/throughput-8gb.json`, `--bench-json docs/benchmarks/demo-1mib-8gb.json` and
`--bench-json docs/benchmarks/wasm-linearity-8gb.json`, commit the files, add rows to the table above, and only then fill the "8 GB Windows no-GPU laptop" column of the README with figures from them.

## How the figures are checked

- `tests/scripts/benchmarks-raw.sh`: every file here has the envelope above and a `commit` of 40 hex digits; `build_inputs_modified` is `false`; the machine label is model and RAM only (no path, no host name, no user name); no file is over 5 MB; every file is listed in
  the table above with its date, short commit and machine, and its `command` appears on this page; the CSV is byte-identical to `docs/score-vs-noise.csv` and its SHA-256 is the one in the provenance file; the sizes in `docs/release.md` for CI run 43667702791 are the ones in its file.
- `tests/docs_numbers.py`: the README's score tables (mixed mean, minimum and maximum; the twelve triggering families; the seven blind spots), its recall statement, "599 of 807", "285 of 288", the 1.99 ratio, the hold tables and the prose counts of `docs/gate.md`,
  the corpus's line and cluster counts, and every `N ms` figure in the README, the CHANGELOG and `docs/` are re-read from these files; a row, a count or a timing with no match fails, unless its paragraph says "raw data not kept".
- `tests/scripts/readme-claims.sh`: the throughput table (all six timings and the header's input size, machine and operating system) equals `throughput-m5pro-48gb.json` and `demo-1mib-m5pro-48gb.json`, and the benchmark time quoted next to the reproduce command equals the best run in `score-vs-noise.provenance.json`.
- `cargo test --features corrupt --test gate_noise` re-computes every hold count in `docs/gate.md` from the generator, so `gate-holds.json` cannot drift from the code without that test failing at the next regeneration.

## Raw data not kept

These figures are quoted somewhere in the repository and have no raw file here. Each is marked in the text where it appears.

- The Sprint 3 and Sprint 5 throughput figures (native `check` 61 and 67 ms, `validate()` 220 and 234 ms, `score_ppm()` 74 and 80 ms, the demo 1,462 ms, and the 6 to 10 percent between them): they were read from logs outside the repository that record the machine but not the commit,
  so they cannot be used (raw data not kept). `throughput-m5pro-48gb.json` and `demo-1mib-m5pro-48gb.json` replace them, measured at `3c0bb4d`.
- The Sprint 3 regeneration of the benchmark (the 35 rows that changed, the hash of the CSV before): the old CSV is in git history, the comparison log is not in the repository.
- Build sizes of local macOS builds in `docs/release.md` and `CHANGELOG.md` (a macOS wheel of 247,060 bytes and an npm tarball of 112,744 bytes on the Mac in Sprint 4, wheels of 254,146, 254,149 and 254,147 bytes in Sprint 5, an sdist of 110,435 bytes): they are build facts, not benchmarks, and a local macOS wheel is not byte-reproducible across checkout paths.
- Peak memory: never recorded on the Mac, and not measured on 8 GB.
- Anything measured on an 8 GB laptop: nothing has been.
