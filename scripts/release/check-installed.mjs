#!/usr/bin/env node
// One real, asserted call against an INSTALLED glyphsift artefact (Sprint 7, D3-02; the release rehearsal's clean-machine check).
//
//   node scripts/release/check-installed.mjs node --project <fresh project dir> --tests <tests dir> --version <x.y.z>
//   node scripts/release/check-installed.mjs cli  --cli <absolute path of the installed binary> --tests <tests dir> --version <x.y.z> --forbid-under <checkout>
//
// `node` mode: the npm tarball was installed into <project> (npm_config_offline, a fresh cache, --ignore-scripts). The package must
// resolve from <project>/node_modules and nowhere else (the proof that the installed artefact, not the source tree, is what runs); then
// a clean and a corrupted Devanagari sample are scored and gated, and every output must equal the bytes committed under tests/determinism.
// `cli` mode: the binary that `cargo install` built from the unpacked packaged .crate files; its path must be absolute, must not be inside
// the checkout, and its `check` and `gate` output must equal the same committed bytes. Exit 0 when every check holds, 1 otherwise.
//
// The two samples: tests/determinism/samples/01-clean-hindi.txt (a clean Hindi text, gate verdict pass) and 03-ocr-corrupted.txt (synthetic
// OCR noise, gate verdict hold); their reports are tests/determinism/expected/NN-*.json and their gate bytes are the lines of
// tests/determinism/gate/expected.jsonl whose case has the note "determinism sample NN-*". Nothing here reads a sibling repository,
// the network or an environment variable.
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { isAbsolute, join, relative, sep } from "node:path";

const [mode, ...rest] = process.argv.slice(2);
const opt = (name) => {
  const i = rest.indexOf(name);
  return i >= 0 ? rest[i + 1] : undefined;
};
const tests = opt("--tests");
const version = opt("--version");
if (!["node", "cli"].includes(mode) || !tests || !version) {
  console.error("usage: check-installed.mjs node|cli --tests <dir> --version <x.y.z> [--project <dir> | --cli <path> --forbid-under <dir>]");
  process.exit(2);
}

let failures = 0;
function check(ok, what) {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) failures += 1;
}

// ---- the committed fixtures ---------------------------------------------------------------------------------
const det = join(tests, "determinism");
const SAMPLES = [
  { name: "01-clean-hindi", verdict: "pass" },
  { name: "03-ocr-corrupted", verdict: "hold" },
];
const gateCases = readFileSync(join(det, "gate", "cases.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const gateExpected = readFileSync(join(det, "gate", "expected.jsonl"), "utf8").split("\n").filter(Boolean);
const fixtures = SAMPLES.map((s) => {
  const bytes = readFileSync(join(det, "samples", `${s.name}.txt`));
  const report = readFileSync(join(det, "expected", `${s.name}.json`));
  const idx = gateCases.findIndex((c) => c.note === `determinism sample ${s.name}` && c.threshold_ppm === null);
  const gate = idx >= 0 ? gateExpected[idx] : undefined;
  return { ...s, bytes, text: bytes.toString("utf8"), report, gate, caseText: idx >= 0 ? gateCases[idx].text : undefined };
});
for (const f of fixtures) {
  check(f.gate !== undefined && f.caseText === f.text, `fixture ${f.name}: the gate case holds the sample's own text`);
  check(f.gate !== undefined && JSON.parse(f.gate).verdict === f.verdict, `fixture ${f.name}: the committed gate bytes say ${f.verdict}`);
}
const VERSION_RE = /^[0-9]+\.[0-9]+\.[0-9]+$/;
check(VERSION_RE.test(version), `version ${version} is plain x.y.z`);

// ---- node: the installed npm package ------------------------------------------------------------------------
if (mode === "node") {
  const project = opt("--project");
  if (!project) {
    console.error("--project is required in node mode");
    process.exit(2);
  }
  const projectReal = realpathSync(project);
  const req = createRequire(join(projectReal, "package.json"));
  const resolved = realpathSync(req.resolve("@airplanemode/glyphsift"));
  const rel = relative(projectReal, resolved);
  console.log(`module: ${resolved}`);
  check(rel !== "" && !rel.startsWith("..") && !isAbsolute(rel) && rel.split(sep)[0] === "node_modules", "the package resolves under the fresh project's node_modules");
  const pkg = JSON.parse(readFileSync(join(projectReal, "node_modules", "@airplanemode", "glyphsift", "package.json"), "utf8"));
  check(pkg.name === "@airplanemode/glyphsift" && pkg.version === version, `the installed package is @airplanemode/glyphsift ${version} (got ${pkg.name} ${pkg.version})`);
  const g = req("@airplanemode/glyphsift");
  for (const f of fixtures) {
    check(g.validate(f.text) + "\n" === f.report.toString("utf8"), `validate(${f.name}) equals the committed report bytes`);
    check(g.gate(f.text) === f.gate, `gate(${f.name}) equals the committed gate bytes (${f.verdict})`);
  }
  check(JSON.parse(g.validate(fixtures[0].text)).score.ppm === 1000000, "the clean sample scores 1000000 ppm");
  check(JSON.parse(g.validate(fixtures[1].text)).score.ppm < 975000, "the corrupted sample scores below the 975000 ppm gate threshold");
}

// ---- cli: the binary installed from the packaged crates -----------------------------------------------------
if (mode === "cli") {
  const cli = opt("--cli");
  const forbid = opt("--forbid-under");
  if (!cli || !forbid) {
    console.error("--cli and --forbid-under are required in cli mode");
    process.exit(2);
  }
  check(isAbsolute(cli) && existsSync(cli), "the CLI is invoked by an absolute path that exists");
  const real = realpathSync(cli);
  const relToCheckout = relative(realpathSync(forbid), real);
  console.log(`cli: ${real}`);
  check(relToCheckout.startsWith("..") || isAbsolute(relToCheckout), "the CLI is not inside the checkout");
  const run = (args, input) => spawnSync(real, args, { input, maxBuffer: 16 * 1024 * 1024 });
  const v = run(["--version"]);
  check(v.status === 0 && v.stdout.toString("utf8") === `glyphsift ${version}\n`, `--version prints 'glyphsift ${version}'`);
  for (const f of fixtures) {
    const c = run(["check", "-"], f.bytes);
    check(c.status === 0 && c.stdout.equals(f.report), `check(${f.name}) prints the committed report bytes`);
    const gt = run(["gate", "-"], f.bytes);
    check(gt.status === 0 && gt.stdout.toString("utf8") === f.gate + "\n", `gate(${f.name}) prints the committed gate bytes (${f.verdict})`);
  }
}

console.log(failures === 0 ? `installed ${mode} check: all checks passed` : `installed ${mode} check: ${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
