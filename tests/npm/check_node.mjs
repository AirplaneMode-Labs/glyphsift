// Checks on the @airplanemode/glyphsift npm tarball and on its offline install (D3-05).
//
//   node tests/npm/check_node.mjs --tgz <tarball> --dir <fresh install dir> [--cli target/release/glyphsift]
//
// <dir> is a fresh empty directory in which `npm init -y` and `npm i <tgz> --ignore-scripts --offline`
// ran. The script checks (exit 1 on any failure, one line per check):
//   - the tarball holds only package/{package.json, README.md, LICENSE, NOTICE, web/*, nodejs/*},
//     is under 5 MB, has no file over 5 MB, no source map and no test data;
//   - package.json is exactly the documented shape: no scripts, dependencies, optionalDependencies,
//     peerDependencies, bin or type; the exports map; sideEffects false; Apache-2.0;
//   - the packaged README carries the honest 'Not published yet' sentence, 'release candidate, not
//     tagged' and an 'After the owner publishes' block, with the bare registry command only after it;
//   - the install holds exactly that one package (npm ls --all, node_modules listing);
//   - a Node call (require and ESM import) validates 'नमस्ते।' to the same bytes `glyphsift check`
//     prints (the native CLI, when --cli is given), and all determinism samples equal their recorded
//     reports.
import { execFileSync, spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const args = process.argv.slice(2);
const opt = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const tgz = opt("--tgz");
const dir = opt("--dir");
const cli = opt("--cli");
if (!tgz || !dir) {
  console.error("usage: node tests/npm/check_node.mjs --tgz <tarball> --dir <install dir> [--cli <glyphsift binary>]");
  process.exit(2);
}

const HONEST =
  "Not published yet: the npm scope @airplanemode and the PyPI and crates.io names are not reserved. " +
  "The commands below were proven from locally built artifacts on macOS arm64 (an npm pack tarball " +
  "installed offline into a fresh empty directory, a wheel installed into a fresh venv); publishing " +
  "to the registries is the owner's step.";
const MAX = 5 * 1024 * 1024;
let failures = 0;
function check(ok, what) {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) failures += 1;
}
function stage(name, fn) {
  try {
    fn();
  } catch (err) {
    check(false, `${name}: ${err instanceof Error ? err.message : String(err)}`);
  }
}

// ---- the tarball -------------------------------------------------------------------------------
stage("tarball", () => {
  check(existsSync(tgz), `the tarball exists (${tgz})`);
  const size = statSync(tgz).size;
  check(size < MAX, `the tarball is under 5 MB (${size} bytes)`);
  // Paths come from `tar -tzf` (the same on bsdtar and GNU tar); sizes come from the files the offline install
  // unpacked from this very tarball (the `-tv` listing differs between tar implementations).
  const paths = execFileSync("tar", ["-tzf", tgz], { encoding: "utf8" })
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.endsWith("/"));
  const pkgRoot = join(dir, "node_modules", "@airplanemode", "glyphsift");
  const listing = paths.map((p) => ({ path: p, size: statSync(join(pkgRoot, p.replace(/^package\//, ""))).size }));
  const allowed = (p) =>
    /^package\/(package\.json|README\.md|LICENSE|NOTICE)$/.test(p) ||
    /^package\/web\/glyphsift(_bg\.wasm|\.js|\.d\.ts|_bg\.wasm\.d\.ts)$/.test(p) ||
    /^package\/nodejs\/glyphsift(_bg\.wasm|\.js|\.d\.ts|_bg\.wasm\.d\.ts)$/.test(p);
  const extra = paths.filter((p) => !allowed(p));
  check(extra.length === 0, `only web/, nodejs/, README.md, LICENSE, NOTICE and package.json are packed${extra.length ? " (extra: " + extra.join(", ") + ")" : ""}`);
  for (const want of ["package/package.json", "package/README.md", "package/LICENSE", "package/NOTICE", "package/web/glyphsift.js", "package/web/glyphsift.d.ts", "package/web/glyphsift_bg.wasm", "package/nodejs/glyphsift.js", "package/nodejs/glyphsift.d.ts", "package/nodejs/glyphsift_bg.wasm"]) {
    check(paths.includes(want), `${want} is in the tarball`);
  }
  check(listing.every((e) => e.size <= MAX), "no packed file is over 5 MB");
  check(!paths.some((p) => /\.map$|\.onnx$|\.safetensors$|\/tests?\/|\/samples?\//.test(p)), "no source map, model file, test data or sample is packed");
});

// ---- package.json and the packaged README -----------------------------------------------------
stage("package.json", () => {
  const pkgDir = join(dir, "node_modules", "@airplanemode", "glyphsift");
  const pkg = JSON.parse(readFileSync(join(pkgDir, "package.json"), "utf8"));
  const cargo = readFileSync(join(root, "Cargo.toml"), "utf8");
  const version = /\[workspace\.package\][\s\S]*?\nversion = "([^"]+)"/.exec(cargo)?.[1];
  check(pkg.name === "@airplanemode/glyphsift", `name is @airplanemode/glyphsift (got ${pkg.name})`);
  check(pkg.version === version, `version ${pkg.version} equals the Cargo.toml workspace version ${version}`);
  check(pkg.license === "Apache-2.0", "license is Apache-2.0");
  check(typeof pkg.repository === "object" && String(pkg.repository.url).includes("AirplaneMode-Labs/glyphsift"), "repository points at AirplaneMode-Labs/glyphsift");
  check(Array.isArray(pkg.keywords) && pkg.keywords.length > 0, "keywords are present");
  for (const f of ["scripts", "dependencies", "optionalDependencies", "peerDependencies", "devDependencies", "bin", "type"]) {
    check(!(f in pkg), `package.json has no '${f}' field`);
  }
  check(pkg.main === "nodejs/glyphsift.js" && pkg.module === "web/glyphsift.js" && pkg.types === "web/glyphsift.d.ts", "main, module and types point at the nodejs and web builds");
  check(pkg.sideEffects === false, "sideEffects is false");
  check(JSON.stringify(pkg.files) === JSON.stringify(["web", "nodejs", "README.md", "LICENSE", "NOTICE"]), "files is [web, nodejs, README.md, LICENSE, NOTICE]");
  const want = {
    ".": {
      types: "./web/glyphsift.d.ts",
      node: { types: "./nodejs/glyphsift.d.ts", default: "./nodejs/glyphsift.js" },
      import: "./web/glyphsift.js",
      default: "./web/glyphsift.js",
    },
    "./web": "./web/glyphsift.js",
    "./nodejs": "./nodejs/glyphsift.js",
    "./web/glyphsift_bg.wasm": "./web/glyphsift_bg.wasm",
  };
  check(JSON.stringify(pkg.exports) === JSON.stringify(want), "the exports map is exactly the documented one");
  const readme = readFileSync(join(pkgDir, "README.md"), "utf8");
  check(readme.includes(HONEST), "the packaged README has the honest 'Not published yet ...' sentence");
  check(readme.includes("release candidate, not tagged"), "the packaged README says 'release candidate, not tagged'");
  check(readme.includes("After the owner publishes"), "the packaged README has an 'After the owner publishes' block");
  check(/^## Limitations/m.test(readme), "the packaged README has a Limitations section");
  const [before] = readme.split("After the owner publishes");
  check(!/npm i(nstall)? @airplanemode|pip install glyphsift|cargo install glyphsift-cli/.test(before), "no bare registry command before the 'After the owner publishes' block");
  const licence = readFileSync(join(pkgDir, "LICENSE"), "utf8");
  check(licence.includes("Apache License") && licence.includes("Version 2.0"), "LICENSE is the Apache 2.0 text");
  check(readFileSync(join(pkgDir, "NOTICE"), "utf8") === readFileSync(join(root, "NOTICE"), "utf8"), "NOTICE equals the repository NOTICE");
  const noticeText = readFileSync(join(pkgDir, "NOTICE"), "utf8");
  check(noticeText.includes("Permission is hereby granted"), "the packaged NOTICE carries the MIT text (TD-28)");
  check(noticeText.includes("zmij 1.0.23") && noticeText.includes("David Tolnay"), "the packaged NOTICE carries the zmij block");
  check(noticeText.includes("memchr 2.8.3") && noticeText.includes("Andrew Gallant"), "the packaged NOTICE carries the memchr block");
  check(!noticeText.includes("does not bundle those texts"), "the packaged NOTICE no longer says the texts are not bundled");
});

// ---- exactly one package in the fresh install ---------------------------------------------------
stage("install", () => {
  const nm = readdirSync(join(dir, "node_modules")).filter((n) => !n.startsWith("."));
  check(JSON.stringify(nm) === JSON.stringify(["@airplanemode"]), `node_modules holds only @airplanemode (found ${nm.join(", ")})`);
  const scoped = readdirSync(join(dir, "node_modules", "@airplanemode"));
  check(JSON.stringify(scoped) === JSON.stringify(["glyphsift"]), `@airplanemode holds only glyphsift (found ${scoped.join(", ")})`);
  const ls = JSON.parse(execFileSync("npm", ["ls", "--all", "--json", "--prefix", dir], { encoding: "utf8" }));
  const deps = Object.keys(ls.dependencies ?? {});
  check(JSON.stringify(deps) === JSON.stringify(["@airplanemode/glyphsift"]), `npm ls --all shows exactly one package (${deps.join(", ")})`);
  check(Object.keys(ls.dependencies["@airplanemode/glyphsift"].dependencies ?? {}).length === 0, "that package has no dependencies");
});

// ---- a real Node call ---------------------------------------------------------------------------
function cliReport(text) {
  const r = spawnSync(resolve(cli), ["check", "-"], { input: text, encoding: "utf8" });
  if (r.status !== 0) throw new Error(`glyphsift check exited ${r.status}: ${r.stderr}`);
  return r.stdout;
}
stage("node call", () => {
  const req = createRequire(join(dir, "package.json"));
  const g = req("@airplanemode/glyphsift");
  const exports = Object.keys(g).filter((k) => typeof g[k] === "function" && !k.startsWith("__") && k !== "initSync" && k !== "default").sort();
  check(JSON.stringify(exports) === JSON.stringify(["clusters", "clusters_json", "issue_kinds", "report_spec", "score_ppm", "validate"]), `require() exposes validate, score_ppm, report_spec, clusters, clusters_json and issue_kinds (${exports.join(", ")})`);
  const report = g.validate("नमस्ते।");
  check(JSON.parse(report).score.ppm === 1000000, "validate('नमस्ते।') scores 1000000");
  check(g.score_ppm("कखग�") === 750000, "score_ppm('कखग\\ufffd') is 750000");
  check(g.report_spec() === "glyphsift.report/0.2", "report_spec() is glyphsift.report/0.2");
  if (cli) {
    check(`${report}\n` === cliReport("नमस्ते।"), "validate('नमस्ते।') is byte-equal to `glyphsift check` output");
  } else {
    check(false, "no --cli given: the byte-equality check against `glyphsift check` was not run");
  }
  const samples = join(root, "tests", "determinism", "samples");
  const expected = join(root, "tests", "determinism", "expected");
  let n = 0;
  for (const name of readdirSync(samples).filter((f) => f.endsWith(".txt")).sort()) {
    const text = new TextDecoder("utf-8", { ignoreBOM: true }).decode(readFileSync(join(samples, name)));
    const want = readFileSync(join(expected, name.replace(/\.txt$/, ".json")), "utf8");
    if (`${g.validate(text)}\n` !== want) check(false, `determinism sample ${name} differs from its recorded report`);
    n += 1;
  }
  check(n >= 13, `the installed package reproduces the recorded reports of all ${n} determinism samples`);
  let threw = false;
  try {
    g.validate("a".repeat(4 * 1024 * 1024 + 1));
  } catch (e) {
    threw = e instanceof Error && /too large/.test(e.message);
  }
  check(threw, "input over 4 MiB throws an Error that says 'too large'");
});

stage("esm import", () => {
  writeFileSync(join(dir, "probe.mjs"), 'import { validate, score_ppm } from "@airplanemode/glyphsift";\nconsole.log(score_ppm("कखग\\ufffd"), JSON.parse(validate("नमस्ते।")).score.ppm);\n');
  const out = execFileSync("node", [join(dir, "probe.mjs")], { cwd: dir, encoding: "utf8" }).trim();
  check(out === "750000 1000000", `an ESM import of the bare specifier works in Node (printed '${out}')`);
});

console.log(failures === 0 ? "npm package checks: all passed" : `npm package checks: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
