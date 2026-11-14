// Browser check of the installed npm package (D3-05): a bundler-free page, served from the fresh
// `npm i` directory, imports ./node_modules/@airplanemode/glyphsift/web/glyphsift.js, runs init() and
// validate(), and must give the same report as `glyphsift check`, with 0 console errors, 0 page
// errors and same-origin requests only. Runs in installed Chrome (channel "chrome").
//
//   PLAYWRIGHT_DIR=<tools/playwright after `npm ci --prefix tools/playwright --ignore-scripts`, or any dir with playwright@1.65.0> \
//     node tests/npm/check_browser.mjs --dir <fresh install dir> --cli target/release/glyphsift
//
// <dir> must contain node_modules/@airplanemode/glyphsift (from `npm i <tgz>`); this script copies
// tests/npm/index.html into it. Exit 1 on any failure.
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, readFileSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { dirname, extname, join, normalize, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const dir = opt("--dir");
const cli = opt("--cli");
const shots = opt("--shots");
if (!dir || !cli) {
  console.error("usage: PLAYWRIGHT_DIR=... node tests/npm/check_browser.mjs --dir <install dir> --cli <glyphsift binary> [--shots <dir>]");
  process.exit(2);
}
const pwDir = process.env.PLAYWRIGHT_DIR;
if (!pwDir) {
  console.error("PLAYWRIGHT_DIR must name a directory with playwright@1.65.0 installed (tools/playwright after `npm ci --prefix tools/playwright --ignore-scripts`)");
  process.exit(2);
}
const { chromium } = createRequire(pathToFileURL(join(resolve(pwDir), "x.js")))("playwright");

let failures = 0;
function check(ok, what) {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) failures += 1;
}

copyFileSync(join(here, "index.html"), join(dir, "index.html"));
const base = resolve(dir);
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".wasm": "application/wasm", ".json": "application/json" };
const server = createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  let rel = decodeURIComponent(url.pathname);
  if (rel === "/") rel = "/index.html";
  const file = normalize(join(base, rel));
  // Only the page and the installed package are served; everything else is a 404.
  const ok = file === join(base, "index.html") || file.startsWith(join(base, "node_modules", "@airplanemode", "glyphsift") + sep);
  if (!ok || !existsSync(file) || !statSync(file).isFile()) {
    res.writeHead(404, { "content-type": "text/plain" });
    res.end("not found");
    return;
  }
  res.writeHead(200, { "content-type": types[extname(file)] ?? "application/octet-stream" });
  res.end(readFileSync(file));
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const origin = `http://127.0.0.1:${server.address().port}`;

const expected = spawnSync(resolve(cli), ["check", "-"], { input: "नमस्ते।", encoding: "utf8" }).stdout;
const browser = await chromium.launch({ channel: "chrome", headless: true });
try {
  const page = await browser.newPage();
  const consoleErrors = [];
  const pageErrors = [];
  const requests = [];
  page.on("console", (m) => {
    if (m.type() === "error" || m.type() === "warning") consoleErrors.push(`${m.type()}: ${m.text()}`);
  });
  page.on("pageerror", (e) => pageErrors.push(String(e)));
  page.on("request", (r) => requests.push(r.url()));
  const failed = [];
  page.on("requestfailed", (r) => failed.push(r.url()));
  await page.goto(`${origin}/index.html`);
  await page.waitForFunction(() => window.__glyphsift || window.__glyphsiftError, null, { timeout: 15000 });
  const err = await page.evaluate(() => window.__glyphsiftError);
  check(!err, `the page imported the installed package and ran init() (${err ?? "no error"})`);
  const r = await page.evaluate(() => window.__glyphsift);
  check(r?.spec === "glyphsift.report/0.2", "report_spec() is glyphsift.report/0.2");
  check(`${r?.report}\n` === expected, "validate('नमस्ते।') in Chrome is byte-equal to `glyphsift check` output");
  check(JSON.parse(r.report).score.ppm === 1000000, "the report scores 1000000");
  check(r?.ppm === 750000, "score_ppm('कखग\\ufffd') is 750000");
  check(JSON.stringify(r?.clusters) === JSON.stringify(["न", "म", "स्ते", "।"]), "clusters('नमस्ते।') is ['न', 'म', 'स्ते', '।']");
  check(consoleErrors.length === 0, `0 console errors or warnings${consoleErrors.length ? ": " + consoleErrors.join(" | ") : ""}`);
  check(pageErrors.length === 0, `0 page errors${pageErrors.length ? ": " + pageErrors.join(" | ") : ""}`);
  check(failed.length === 0, `0 failed requests${failed.length ? ": " + failed.join(" | ") : ""}`);
  const foreign = requests.filter((u) => !u.startsWith(origin + "/"));
  check(foreign.length === 0, `same-origin requests only (${requests.length} requests)${foreign.length ? ", foreign: " + foreign.join(" | ") : ""}`);
  check(requests.some((u) => u.endsWith("/node_modules/@airplanemode/glyphsift/web/glyphsift_bg.wasm")), "the WASM module came from the installed package");
  if (shots) await page.screenshot({ path: join(shots, "npm-browser.png") });
} finally {
  await browser.close();
  server.close();
}
console.log(failures === 0 ? "npm browser check: all passed" : `npm browser check: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
