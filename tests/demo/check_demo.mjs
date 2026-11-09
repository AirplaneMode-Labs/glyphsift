// Drives the built demo (demo/dist) in installed Google Chrome, served under /glyphsift/ by a server
// that answers 404 for every other path, and checks what the demo claims.
//
//   scripts/build-demo.sh
//   PLAYWRIGHT_DIR=/path/to/dir-with-node_modules-playwright \
//     node tests/demo/check_demo.mjs [--cli target/release/glyphsift] [--evidence out.json]
//
// Playwright is not a dependency of this repository: install it anywhere ("npm i playwright" in a
// scratch directory) and point PLAYWRIGHT_DIR at that directory. Chrome is used through
// `channel: "chrome"`, so no browser is downloaded. Exit 0 when every check passes.
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, extname, join, normalize, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const arg = (name, fallback) => {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : fallback;
};
const dist = resolve(root, arg("--dist", "demo/dist"));
const cli = resolve(root, arg("--cli", "target/release/glyphsift"));
const evidencePath = arg("--evidence", "");
const pwDir = process.env.PLAYWRIGHT_DIR;
if (!pwDir) {
  console.error("set PLAYWRIGHT_DIR to a directory whose node_modules contains playwright");
  process.exit(2);
}
const { chromium } = createRequire(join(resolve(pwDir), "/"))("playwright");

const EXPECTED_CSP =
  "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self'; img-src 'self' data: blob:; connect-src 'self'; worker-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'";
const LIMIT = 1048576;
const BASE = "/glyphsift/";

const results = [];
function check(ok, what, detail = "") {
  results.push({ ok: Boolean(ok), what, detail });
  console.log(`${ok ? "ok  " : "FAIL"} ${what}${detail ? ` (${detail})` : ""}`);
}

// ---- a server that serves dist under /glyphsift/ and nothing else --------------------------------
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".json": "application/json", ".wasm": "application/wasm" };
const served = [];
const server = createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  served.push(url.pathname);
  if (url.pathname === BASE.slice(0, -1)) {
    res.writeHead(301, { location: BASE }).end();
    return;
  }
  if (!url.pathname.startsWith(BASE)) {
    res.writeHead(404, { "content-type": "text/plain" }).end("404");
    return;
  }
  let rel = decodeURIComponent(url.pathname.slice(BASE.length));
  if (rel === "" || rel.endsWith("/")) rel += "index.html";
  const file = resolve(dist, normalize(rel));
  if (!file.startsWith(dist + sep)) {
    res.writeHead(404).end("404");
    return;
  }
  try {
    if (!statSync(file).isFile()) throw new Error("not a file");
    res.writeHead(200, { "content-type": MIME[extname(file)] ?? "application/octet-stream" }).end(readFileSync(file));
  } catch {
    res.writeHead(404, { "content-type": "text/plain" }).end("404");
  }
});
await new Promise((ok) => server.listen(0, "127.0.0.1", ok));
const origin = `http://127.0.0.1:${server.address().port}`;

const fmt4 = (ppm) => `${Math.floor(ppm / 1e6)}.${String(Math.floor((ppm % 1e6) / 100)).padStart(4, "0")}`;
const cliReport = (text) => execFileSync(cli, ["check", "-"], { input: Buffer.from(text, "utf8"), maxBuffer: 1 << 28 }).toString("utf8");

// ---- the browser ---------------------------------------------------------------------------------
const browser = await chromium.launch({ channel: "chrome", headless: true });
const page = await (await browser.newContext()).newPage();
const consoleErrors = [];
const requests = [];
page.on("console", (m) => m.type() === "error" && consoleErrors.push(m.text()));
page.on("pageerror", (e) => consoleErrors.push(`pageerror: ${e.message}`));
page.on("request", (r) => requests.push(r.url()));
page.on("requestfailed", (r) => consoleErrors.push(`requestfailed: ${r.url()}`));

let ready = false;
try {
  await page.goto(`${origin}${BASE}`, { waitUntil: "load" });
  await page.waitForFunction(() => document.body.dataset.ready === "true", null, { timeout: 15000 });
  ready = true;
} catch (err) {
  check(false, "the demo loads and signals ready", String(err.message).split("\n")[0]);
}

async function text(sel) {
  return (await page.locator(sel).first().textContent()) ?? "";
}

if (ready) {
  // sub-path serving
  const get = async (p) => (await fetch(`${origin}${p}`, { redirect: "manual" })).status;
  check((await get("/")) === 404 && (await get("/pkg/glyphsift.js")) === 404 && (await get("/index.html")) === 404, "the server answers 404 outside /glyphsift/");
  check((await get(`${BASE}pkg/glyphsift_bg.wasm`)) === 200, "the wasm module is served under /glyphsift/pkg/");

  // CSP and status line
  const csp = await page.locator('meta[http-equiv="Content-Security-Policy"]').getAttribute("content");
  check(csp === EXPECTED_CSP, "the strict meta CSP is unchanged", csp === EXPECTED_CSP ? "" : csp);
  const status = await text("#build-line");
  check(/Built from main at (local|[0-9a-f]{12})\b/.test(status) && status.includes("glyphsift.report/0.2"), "the status line shows the build id and report 0.2", status.trim());
  check((await text("#not-yet h2")).trim() === "What this demo does not do yet", "the not-yet box is headed exactly 'What this demo does not do yet'");
  const notYet = (await text("#not-yet")).toLowerCase();
  for (const word of ["heatmap", "devanagari only", "service worker", "drag"]) check(notYet.includes(word), `the not-yet box mentions "${word}"`);
  check(!notYet.includes("not implemented") && !notYet.includes("unimplemented"), "the not-yet box no longer claims validate() is missing");

  // samples
  const keys = await page.locator("#samples button[data-sample]").evaluateAll((els) => els.map((e) => e.dataset.sample));
  check(keys.length >= 4 && keys.includes("adversarial"), "there are at least four samples, one of them adversarial", keys.join(", "));
  const evidence = { origin, samples: {} };
  let calls = Number((await text("#call-count")).trim());
  for (const key of keys) {
    await page.click(`#samples button[data-sample="${key}"]`);
    const input = await page.inputValue("#text");
    const json = await text("#json-out");
    const want = cliReport(input);
    const report = JSON.parse(want);
    check(json === want.replace(/\n$/, ""), `${key}: the demo's JSON block equals the CLI report byte for byte`, `${Buffer.byteLength(want)} bytes`);
    check((await text("#score-value")).trim() === fmt4(report.score.ppm), `${key}: the score is shown as ${fmt4(report.score.ppm)} (integer formatting)`, (await text("#score-value")).trim());
    const rows = await page.locator("#line-rows tr").count();
    check(rows === Math.min(report.lines.length, 500), `${key}: one table row per line`, `${rows} rows for ${report.lines.length} lines`);
    const rowScores = await page.locator("#line-rows tr td.line-score").allTextContents();
    check(rowScores.every((s, i) => s.trim() === fmt4(report.lines[i].score_ppm)), `${key}: every line shows its own score`);
    const issuesText = await text("#line-rows");
    const kinds = [...new Set(report.issues.map((i) => i.kind))];
    check(kinds.every((k) => issuesText.includes(k)), `${key}: every rule that fired is named in the per-line issues`, kinds.join(", "));
    const ruleItems = await page.locator("#issue-kinds li").count();
    check(ruleItems === 16, `${key}: all 16 rules are listed`);
    const counted = await page.locator("#issue-kinds li[data-count]").evaluateAll((els) => Object.fromEntries(els.map((e) => [e.dataset.kind, Number(e.dataset.count)])));
    check(Object.entries(report.summary.by_kind).every(([k, n]) => counted[k] === n) && Object.values(counted).reduce((a, b) => a + b, 0) === report.summary.issue_count, `${key}: the rule list counts match summary.by_kind`);
    calls += 1;
    evidence.samples[key] = { bytes: Buffer.byteLength(input), score_ppm: report.score.ppm, lines: report.lines.length, issues: report.summary.issue_count };
  }
  check(Number((await text("#call-count")).trim()) === calls, "validate() call counter matches the samples run", `${calls}`);

  // the size limit
  const before = Number((await text("#call-count")).trim());
  await page.evaluate((value) => {
    const area = document.querySelector("#text");
    area.value = value;
    area.dispatchEvent(new Event("input", { bubbles: true }));
  }, "a".repeat(LIMIT + 1));
  const note = await text("#input-note");
  check(/refused/i.test(note) && note.includes("1,048,576"), "1 MiB + 1 byte is refused with a message naming the limit", note.trim());
  check(Number((await text("#call-count")).trim()) === before, "wasm validate() was not called for the refused input");
  check((await text("#score-value")).trim() === "—", "no stale score is shown for a refused input");
  const unit = "नमस्ते दुनिया।\n";
  const exact = unit.repeat(Math.floor(LIMIT / Buffer.byteLength(unit)));
  const padded = exact + " ".repeat(LIMIT - Buffer.byteLength(exact));
  check(Buffer.byteLength(padded) === LIMIT, "the accepted-size input is exactly 1,048,576 bytes");
  // Set the value directly: Playwright's fill() types into a textarea whose layout, for 1 MiB of
  // Devanagari, is the browser's cost rather than the demo's.
  const t0 = Date.now();
  await page.evaluate((value) => {
    const area = document.querySelector("#text");
    area.value = value;
    area.dispatchEvent(new Event("input", { bubbles: true }));
  }, padded);
  await page.waitForFunction(() => document.querySelector("#score-value")?.textContent.trim() !== "—", null, { timeout: 60000 });
  console.log(`     1 MiB validated and rendered in ${Date.now() - t0} ms`);
  check(!/refused/i.test(await text("#input-note")) && Number((await text("#call-count")).trim()) === before + 1, "exactly 1 MiB is accepted and validated once");
  check((await page.locator("#line-rows tr").count()) <= 500, "a huge input renders at most 500 line rows");
  check((await text("#json-note")).toLowerCase().includes("truncated") || (await text("#json-out")).length > 0, "a huge report shows a truncated JSON block with a note");

  // markup in the pasted text stays text
  await page.fill("#text", `<img src=x onerror="window.__xss=1"><script>window.__xss=2</script> क्\u{200D} "quotes" & <b>bold</b>\n`);
  await page.waitForTimeout(300);
  check((await page.evaluate(() => window.__xss)) === undefined, "markup in pasted text does not execute");
  check((await page.locator("main img, main b, main script").count()) === 0, "markup in pasted text creates no elements");
  check((await text("#line-rows")).includes("<img src=x"), "the pasted markup is shown as plain text");

  // network and console
  const external = requests.filter((u) => !u.startsWith(origin) && !u.startsWith("data:"));
  check(external.length === 0, "every request is same-origin", external.join(", "));
  const odd = requests.filter((u) => u.startsWith(origin) && !new URL(u).pathname.startsWith(BASE));
  check(odd.length === 0, "every request is under /glyphsift/", odd.join(", "));
  check(consoleErrors.length === 0, "zero console errors", consoleErrors.join(" | "));
  evidence.requests = [...new Set(requests.map((u) => new URL(u).pathname))];

  // the source gate
  let gate = true;
  try {
    execFileSync(join(root, "scripts", "check-demo-sources.sh"), { stdio: "pipe" });
  } catch {
    gate = false;
  }
  check(gate, "scripts/check-demo-sources.sh passes (no innerHTML, outerHTML or insertAdjacentHTML in demo/*.js)");
  if (evidencePath) writeFileSync(evidencePath, JSON.stringify({ ...evidence, results }, null, 2));
}

await browser.close();
server.close();
const failed = results.filter((r) => !r.ok).length;
console.log(failed === 0 ? `demo: all ${results.length} checks passed` : `demo: ${failed} of ${results.length} checks FAILED`);
process.exit(failed === 0 ? 0 : 1);
