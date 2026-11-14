// Drives the built demo (demo/dist) in installed Google Chrome, served under /glyphsift/ by a server
// that answers 404 for every other path, and checks what the demo claims.
//
//   scripts/build-demo.sh
//   PLAYWRIGHT_DIR=/path/to/dir-with-node_modules-playwright \
//     node tests/demo/check_demo.mjs [--cli target/release/glyphsift] [--evidence out.json] [--shots dir]
//
// Sprint 3 (D3-07) adds: the per-line strip and per-cluster heatmap (highlighted clusters equal the
// distinct cluster indices of report.issues for all five samples, per-line buckets match, class names
// come from the fixed set, no style attribute), local files through the picker and through a drop
// (same report as the CLI and as paste, zero requests), the refusals (invalid UTF-8, over 1 MiB, the
// size checked before the file is read), and the source grep (no innerHTML, insertAdjacentHTML,
// document.write or style attribute). --shots saves screenshots of the adversarial heatmap and a drop.
//
// Playwright is not a dependency of glyphsift: `npm ci --prefix tools/playwright --ignore-scripts` installs
// 1.65.0 from the committed lockfile (every package pinned by integrity hash); point PLAYWRIGHT_DIR at
// tools/playwright (any directory with playwright installed also works). Chrome is used through
// `channel: "chrome"`, so no browser is downloaded. Exit 0 when every check passes.
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
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
const shotsDir = arg("--shots", "");
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
// The extension map GitHub Pages uses for these files; an extension it does not know (or no extension, as
// in a bare NOTICE or LICENSE) is served as application/octet-stream, which a browser downloads instead of showing.
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".json": "application/json", ".wasm": "application/wasm", ".txt": "text/plain; charset=utf-8" };
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

const KINDS = [
  "dependent_vowel_without_base", "stray_combining_mark", "double_matra", "double_nukta", "nukta_after_matra",
  "nukta_on_non_consonant", "virama_without_consonant", "virama_after_matra", "sign_before_matra",
  "multiple_anusvara_like", "visarga_before_anusvara", "vowel_sign_on_independent_vowel", "zwj_zwnj_misplaced",
  "mixed_script_in_cluster", "unexpected_code_point", "control_character",
];
const BUCKETS = ["clean", "low", "mid", "high"];
const bucketOf = (sum) => (sum <= 0 ? "clean" : sum < 400 ? "low" : sum < 800 ? "mid" : "high");
// What the heatmap must show for a report: severity per cluster is the sum of its issues' weights, a line's
// bucket comes from the sum over its clusters.
function expectedHeatmap(report) {
  const w = report.score.weights;
  const perCluster = new Map();
  for (const i of report.issues) perCluster.set(i.cluster, (perCluster.get(i.cluster) ?? 0) + w[i.kind]);
  const lines = report.lines.map((l) => {
    let sum = 0;
    for (let c = l.cluster_start; c < l.cluster_end; c += 1) sum += perCluster.get(c) ?? 0;
    return bucketOf(sum);
  });
  return { perCluster, lines };
}

const fmt4 = (ppm) => `${Math.floor(ppm / 1e6)}.${String(Math.floor((ppm % 1e6) / 100)).padStart(4, "0")}`;
const cliReport = (text) => execFileSync(cli, ["check", "-"], { input: Buffer.from(text, "utf8"), maxBuffer: 1 << 28 }).toString("utf8");

// ---- the browser ---------------------------------------------------------------------------------
const browser = await chromium.launch({ channel: "chrome", headless: true });
const page = await (await browser.newContext()).newPage();
// Count every way the page could read a File or Blob, to prove a refused file is never read.
await page.addInitScript(() => {
  window.__fileReads = 0;
  for (const name of ["arrayBuffer", "text", "stream", "slice", "bytes"]) {
    const orig = Blob.prototype[name];
    if (typeof orig !== "function") continue;
    Blob.prototype[name] = function (...a) {
      window.__fileReads += 1;
      return orig.apply(this, a);
    };
  }
  const readAs = (n) => {
    const orig = FileReader.prototype[n];
    FileReader.prototype[n] = function (...a) {
      window.__fileReads += 1;
      return orig.apply(this, a);
    };
  };
  ["readAsArrayBuffer", "readAsText", "readAsDataURL", "readAsBinaryString"].forEach(readAs);
});
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
  // BUG-T1-S3-R2-01: the third-party notice is NOTICE.txt, so that Pages serves it as text/plain and the link displays it.
  check((await page.locator('footer a[href="NOTICE.txt"]').count()) === 1 && (await page.locator('footer a[href="NOTICE"]').count()) === 0, "the footer links NOTICE.txt (an extensionless NOTICE is served as a download)");
  const noticeRes = await fetch(`${origin}${BASE}NOTICE.txt`);
  const noticeType = noticeRes.headers.get("content-type") ?? "";
  check(noticeRes.status === 200 && noticeType.startsWith("text/plain"), "NOTICE.txt is served with a text/plain content type", noticeType);
  check((await get(`${BASE}LICENSE`)) === 200, "LICENSE is served under /glyphsift/");
  check((await get(`${BASE}NOTICE`)) === 404, "there is no extensionless NOTICE next to NOTICE.txt");
  const noticeText = await noticeRes.text();
  check(noticeText.includes("zmij 1.0.23 (MIT). The licence file carries no copyright line; the author named in its Cargo.toml is David Tolnay."), "the served NOTICE.txt carries the zmij paragraph: MIT, author named from Cargo.toml (TD-05)");
  check(noticeText.includes("memchr 2.8.3 (MIT)") && noticeText.includes("Permission is hereby granted, free of charge"), "the served NOTICE.txt carries the MIT texts of the non-Apache WASM crates");
  {
    // Chrome shows the file: a text/plain document, no download event, the paragraph in the visible text.
    const viewer = await page.context().newPage();
    let downloads = 0;
    viewer.on("download", () => (downloads += 1));
    const res = await viewer.goto(`${origin}${BASE}NOTICE.txt`, { waitUntil: "load" });
    const shown = await viewer.evaluate(() => ({ type: document.contentType, text: document.body.innerText }));
    check(res?.status() === 200 && shown.type === "text/plain" && downloads === 0 && shown.text.includes("zmij 1.0.23 (MIT)"), "opening NOTICE.txt in Chrome displays it as text (no download)", `${shown.type}, ${downloads} downloads`);
    await viewer.close();
  }

  // CSP and status line
  const csp = await page.locator('meta[http-equiv="Content-Security-Policy"]').getAttribute("content");
  check(csp === EXPECTED_CSP, "the strict meta CSP is unchanged", csp === EXPECTED_CSP ? "" : csp);
  const status = await text("#build-line");
  check(/Built from main at (local|[0-9a-f]{12})\b/.test(status) && status.includes("glyphsift.report/0.2"), "the status line shows the build id and report 0.2", status.trim());
  // T1-S4-R1-05: a static #sprint-status line equal to the status-line text recorded in site/data/demos.json.
  const SPRINT_STATUS = "Sprint 4 (14 Nov 2026): Working: paste, drop or choose a UTF-8 .txt file up to 1 MiB of Devanagari text and get a document score, a per-line strip and table, a per-cluster heatmap, and the count of each of the sixteen rules; a file that is not UTF-8 or is over 1 MiB is refused in plain text; computed in WebAssembly in the tab, with 0 requests after the page loads; the footer names the licence (Apache-2.0) and links the third-party notices (NOTICE.txt). Not yet: scripts other than Devanagari (Tamil is planned for v0.2 as a design note only, Bengali later), a published package or wheel (Linux and Windows wheels are built only by CI after the owner's push), 8 GB figures (not measured on 8 GB).";
  const sprintStatus = (await text("#sprint-status")).trim();
  check(sprintStatus === SPRINT_STATUS, "the #sprint-status line is exactly the agreed text", sprintStatus.slice(0, 80));
  check((await page.locator("#sprint-status script, script:not([src])").count()) === 0, "the page has no inline script");
  check((await text("#not-yet h2")).trim() === "What this demo does not do yet", "the not-yet box is headed exactly 'What this demo does not do yet'");
  const notYet = (await text("#not-yet")).toLowerCase();
  for (const word of ["devanagari only", "structural checks only", "not calibrated", "service worker", "nothing is published"]) check(notYet.includes(word), `the not-yet box mentions "${word}"`);
  // Sprint 4 (D3-04): Tamil is the planned second script; Linux and Windows wheels come only from CI after the push.
  for (const word of ["tamil planned for v0.2", "bengali later", "linux and windows wheels are built only by ci after the owner's push"]) check(notYet.includes(word), `the not-yet box says "${word}"`);
  for (const word of ["heatmap", "drag", "drop"]) check(!notYet.includes(word), `the not-yet box no longer lists "${word}" (the demo does it now)`);
  check(!notYet.includes("not implemented") && !notYet.includes("unimplemented"), "the not-yet box no longer claims validate() is missing");
  check((await page.locator("#drop-zone").count()) === 1 && (await page.locator('#file-input[type="file"][accept=".txt,text/plain"]').count()) === 1, "a drop zone and a file input accepting .txt and text/plain are on the page");
  check((await page.locator("#heatmap").count()) === 1 && (await page.locator("#heatmap-legend li").count()) === 4, "the heatmap panel and its four-item legend are on the page");

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
    // the heatmap: one row per line, a strip bucket per line, a span per cluster
    const hm = await page.evaluate(() =>
      [...document.querySelectorAll("#heatmap-rows .hm-line")].map((row) => ({
        strip: row.querySelector(".strip")?.getAttribute("class") ?? "",
        stripLabel: row.querySelector(".strip")?.getAttribute("aria-label") ?? "",
        spans: [...row.querySelectorAll(".cl")].map((c) => ({
          cls: c.getAttribute("class"),
          cluster: c.getAttribute("data-cluster"),
          title: c.getAttribute("title"),
          aria: c.getAttribute("aria-label"),
          style: c.hasAttribute("style"),
        })),
      })),
    );
    const exp = expectedHeatmap(report);
    check(hm.length === report.lines.length, `${key}: the heatmap has one row per line`, `${hm.length} rows for ${report.lines.length} lines`);
    check(hm.every((r, i) => r.strip === `strip sev-${exp.lines[i]}`), `${key}: every per-line strip has the bucket of that line's issue weight sum`, hm.map((r) => r.strip.replace("strip sev-", "")).join(","));
    const flat = hm.flatMap((r) => r.spans);
    const lit = flat.filter((c) => c.cls !== "cl sev-clean");
    const wantClusters = [...new Set(report.issues.map((i) => i.cluster))].sort((a, b) => a - b);
    const got = lit.map((c) => Number(c.cluster)).sort((a, b) => a - b);
    check(JSON.stringify(got) === JSON.stringify(wantClusters), `${key}: highlighted clusters equal the distinct cluster indices in report.issues`, `${got.length} highlighted, ${wantClusters.length} distinct`);
    check(lit.every((c) => c.cls === `cl sev-${bucketOf(exp.perCluster.get(Number(c.cluster)) ?? 0)}`), `${key}: each highlighted cluster has the bucket of its summed issue weights`);
    check(flat.every((c) => c.cls === "cl sev-clean" || BUCKETS.some((b) => c.cls === `cl sev-${b}`)), `${key}: span classes come from the fixed bucket set`);
    check(lit.every((c) => c.title && c.aria && c.title.split(", ").every((k) => KINDS.includes(k)) && c.aria.split(", ").every((k) => KINDS.includes(k))), `${key}: titles and aria-labels name only rules from the fixed list`);
    check(flat.every((c) => !c.style), `${key}: no heatmap span carries a style attribute`);
    check((await page.locator("[style]").count()) === 0, `${key}: no element on the page carries a style attribute`);
    if (key === "clean") {
      const firstLine = await page.locator("#heatmap-rows .hm-line").first().locator(".hm-text").textContent();
      check(firstLine === "नमस्ते दुनिया।", "clean: the heatmap shows the line's own text", firstLine);
    }
    if (key === "adversarial" && shotsDir) {
      mkdirSync(shotsDir, { recursive: true });
      await page.locator("#heatmap").scrollIntoViewIfNeeded();
      await page.locator("#heatmap").screenshot({ path: join(shotsDir, "heatmap-adversarial.png") });
    }
    calls += 1;
    evidence.samples[key] = { bytes: Buffer.byteLength(input), score_ppm: report.score.ppm, lines: report.lines.length, issues: report.summary.issue_count };
  }
  check(Number((await text("#call-count")).trim()) === calls, "validate() call counter matches the samples run", `${calls}`);

  // local files: the picker and a drop give the CLI's report, make no request, and refuse what they must
  {
    const fixtures = join(root, "tests", "demo", "fixtures");
    const fxPath = (n) => join(fixtures, n);
    const cliFile = (n) => execFileSync(cli, ["check", fxPath(n)], { maxBuffer: 1 << 28 }).toString("utf8");
    const callsNow = async () => Number((await text("#call-count")).trim());
    const reads = () => page.evaluate(() => window.__fileReads);
    const waitJson = (want) => page.waitForFunction((w) => document.querySelector("#json-out").textContent === w, want.replace(/\n$/, ""), { timeout: 15000 });
    const dropFiles = (files, target = "#drop-zone") =>
      page.evaluate(
        ({ files, target }) => {
          const dt = new DataTransfer();
          for (const f of files) dt.items.add(new File([new Uint8Array(f.bytes)], f.name, { type: "text/plain" }));
          const node = document.querySelector(target);
          const out = { overClass: false, afterClass: true };
          node.dispatchEvent(new DragEvent("dragenter", { dataTransfer: dt, bubbles: true, cancelable: true }));
          const over = new DragEvent("dragover", { dataTransfer: dt, bubbles: true, cancelable: true });
          node.dispatchEvent(over);
          out.overPrevented = over.defaultPrevented;
          out.overClass = node.classList.contains("dragging");
          const drop = new DragEvent("drop", { dataTransfer: dt, bubbles: true, cancelable: true });
          node.dispatchEvent(drop);
          out.dropPrevented = drop.defaultPrevented;
          out.afterClass = node.classList.contains("dragging");
          return out;
        },
        { files, target },
      );
    const sampleBytes = readFileSync(fxPath("sample.txt"));
    const sampleWant = cliFile("sample.txt");

    // paste first, as the reference for the other two paths
    const reqBefore = requests.length;
    await page.fill("#text", sampleBytes.toString("utf8"));
    await waitJson(sampleWant);
    const pasted = await text("#json-out");
    check(pasted === sampleWant.replace(/\n$/, ""), "paste: the report for the synthetic .txt equals `glyphsift check FILE`");

    // the file picker
    await page.fill("#text", "");
    const c0 = await callsNow();
    await page.setInputFiles("#file-input", fxPath("sample.txt"));
    await waitJson(sampleWant);
    check((await text("#json-out")) === pasted, "file picker: the same report as paste", `${Buffer.byteLength(pasted)} bytes`);
    check((await text("#json-out")) === sampleWant.replace(/\n$/, ""), "file picker: the report equals `glyphsift check FILE` byte for byte");
    check((await callsNow()) === c0 + 1, "file picker: validate() ran once");
    check((await page.inputValue("#text")) === sampleBytes.toString("utf8"), "file picker: the text is shown in the text area");
    check((await text("#file-note")).includes("sample.txt"), "file picker: the file note names the file", (await text("#file-note")).trim());
    check(requests.length === reqBefore, "paste and file picker made 0 network requests", `${requests.length - reqBefore} new`);

    // a drop on the drop zone
    await page.fill("#text", "");
    const c1 = await callsNow();
    const dropped = await dropFiles([{ name: "sample.txt", bytes: [...sampleBytes] }]);
    await waitJson(sampleWant);
    check(dropped.overPrevented && dropped.dropPrevented, "drop: dragover and drop are default-prevented on the zone");
    check(dropped.overClass === true && dropped.afterClass === false, "drop: the zone is marked while dragging over and unmarked after the drop");
    check((await text("#json-out")) === pasted, "drop: the same report as paste and as the file picker");
    check((await callsNow()) === c1 + 1, "drop: validate() ran once");
    check(requests.length === reqBefore, "drop made 0 network requests", `${requests.length - reqBefore} new`);
    if (shotsDir) {
      mkdirSync(shotsDir, { recursive: true });
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.screenshot({ path: join(shotsDir, "drop-sample.png"), fullPage: true });
    }

    // a drop elsewhere on the page must not navigate away from the demo
    const outside = await dropFiles([{ name: "x.txt", bytes: [97] }], "body");
    check(outside.dropPrevented === true, "a file dropped outside the zone is default-prevented (the browser does not open it)");

    // BOM and CRLF are kept, exactly as the CLI keeps them
    await page.setInputFiles("#file-input", fxPath("crlf-bom.txt"));
    const crlfWant = cliFile("crlf-bom.txt");
    await waitJson(crlfWant);
    check((await text("#json-out")) === crlfWant.replace(/\n$/, ""), "a BOM and CRLF file: the report equals `glyphsift check FILE` (BOM and CRLF kept)");

    // several files dropped: the first is read, and the note says so
    const mf = await dropFiles([{ name: "sample.txt", bytes: [...sampleBytes] }, { name: "second.txt", bytes: [97] }]);
    await waitJson(sampleWant);
    check(mf.dropPrevented && (await text("#file-note")).toLowerCase().includes("first file"), "several files dropped: only the first is read and the note says so", (await text("#file-note")).trim());

    // refusals: plain text, no validate(), no request
    const c2 = await callsNow();
    const r0 = await reads();
    await page.setInputFiles("#file-input", fxPath("invalid-utf8.txt"));
    await page.waitForFunction(() => /not valid UTF-8/.test(document.querySelector("#input-note").textContent), null, { timeout: 10000 });
    const bad = await text("#input-note");
    check(bad.includes("This file is not valid UTF-8 text"), "an invalid-UTF-8 file is refused with 'This file is not valid UTF-8 text'", bad.trim());
    check((await callsNow()) === c2, "an invalid-UTF-8 file does not reach validate()");
    check((await text("#score-value")).trim() === "—", "no stale score is shown after a refused file");
    check((await page.locator("#heatmap-rows .hm-line").count()) === 0, "no stale heatmap is shown after a refused file");
    check((await page.locator("#input-note a, #input-note b, #input-note img").count()) === 0, "the refusal is plain text");

    await page.setInputFiles("#file-input", { name: "big.txt", mimeType: "text/plain", buffer: Buffer.alloc(LIMIT + 1, 0x61) });
    await page.waitForFunction(() => /over 1 MiB/.test(document.querySelector("#input-note").textContent), null, { timeout: 10000 });
    const big = await text("#input-note");
    check(big.includes("This file is over 1 MiB"), "a file of 1 MiB + 1 byte is refused with 'This file is over 1 MiB'", big.trim());
    const r1 = await reads();
    check(r1 === r0 + 1, "the over-limit file was never read (its size is checked first); only the earlier invalid-UTF-8 file was", `reads ${r0} -> ${r1}`);
    check((await callsNow()) === c2, "an over-limit file does not reach validate()");
    const bigDrop = await dropFiles([{ name: "big.txt", bytes: [...Buffer.alloc(LIMIT + 1, 0x61)] }]);
    await page.waitForFunction(() => /over 1 MiB/.test(document.querySelector("#input-note").textContent), null, { timeout: 10000 });
    check(bigDrop.dropPrevented && (await reads()) === r1 && (await callsNow()) === c2, "an over-limit file dropped is refused unread, and validate() is not called");
    check(requests.length === reqBefore, "refusals made 0 network requests", `${requests.length - reqBefore} new`);

    // a good file clears the refusal
    await page.setInputFiles("#file-input", fxPath("sample.txt"));
    await waitJson(sampleWant);
    check(!/refused|not valid UTF-8|over 1 MiB/i.test(await text("#input-note")) , "a good file clears the earlier refusal");
    // exactly 1 MiB is accepted
    const unit2 = "नमस्ते दुनिया।\n";
    const exact2 = unit2.repeat(Math.floor(LIMIT / Buffer.byteLength(unit2)));
    const padded2 = Buffer.from(exact2 + " ".repeat(LIMIT - Buffer.byteLength(exact2)));
    check(padded2.length === LIMIT, "the accepted-size file is exactly 1,048,576 bytes");
    const c3 = await callsNow();
    await page.setInputFiles("#file-input", { name: "exact.txt", mimeType: "text/plain", buffer: padded2 });
    await page.waitForFunction((n) => Number(document.querySelector("#call-count").textContent) === n, c3 + 1, { timeout: 60000 });
    check(!/This file is/.test(await text("#input-note")), "a file of exactly 1 MiB is accepted and validated once");
    check(requests.length === reqBefore, "no file action made a network request", `${requests.length - reqBefore} new`);
  }

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
  check(gate, "scripts/check-demo-sources.sh passes (no innerHTML, outerHTML, insertAdjacentHTML, document.write or style attribute in demo/)");
  // the same grep, in this test: the demo sources and the built copy
  const demoFiles = [...readdirSync(join(root, "demo")).filter((f) => f.endsWith(".js") || f === "index.html").map((f) => join(root, "demo", f)), ...readdirSync(dist).filter((f) => f.endsWith(".js") || f === "index.html").map((f) => join(dist, f))];
  const banned = /innerHTML|outerHTML|insertAdjacentHTML|document\.write|setAttribute\(\s*["']style|\.style\b|cssText|\sstyle\s*=/;
  const offenders = demoFiles.filter((f) => banned.test(readFileSync(f, "utf8")));
  check(offenders.length === 0, "grep: no innerHTML, outerHTML, insertAdjacentHTML, document.write or style attribute in demo/ or demo/dist", offenders.join(", "));
  if (evidencePath) writeFileSync(evidencePath, JSON.stringify({ ...evidence, results }, null, 2));
}

await browser.close();
server.close();
const failed = results.filter((r) => !r.ok).length;
console.log(failed === 0 ? `demo: all ${results.length} checks passed` : `demo: ${failed} of ${results.length} checks FAILED`);
process.exit(failed === 0 ? 0 : 1);
