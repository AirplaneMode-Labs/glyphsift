// glyphsift demo. Everything runs in this tab: the WASM module is loaded from ./pkg/, the text never
// leaves the page, and the only network requests are for this page's own files.
//
// Every string that comes from the report, from a sample, from a local file or from the pasted text
// reaches the page through textContent or createTextNode, never as markup, and every attribute is set
// with setAttribute from a fixed set of values (scripts/check-demo-sources.sh enforces it).
//
// Local files (Sprint 3): the drop zone and the file picker read one file in this tab with
// File.arrayBuffer(), after checking file.size against the 1 MiB limit (an oversized file is never
// read), decode it with a fatal UTF-8 decoder, and validate exactly the decoded text, so the report is
// byte for byte what `glyphsift check FILE` prints. Nothing is uploaded.
//
// The Gate tab (Sprint 5): the same text goes through gate(text, threshold_ppm) in the WASM module, and the
// canonical JSON it returns (byte for byte what `glyphsift gate -` prints) and the numbers in it are shown as text.
// The module itself refuses a string with an unpaired surrogate (a TypeError, checked with isWellFormed before
// the Rust code is called) and a threshold that is not a whole number from 0 to 1,000,000; the demo checks the
// threshold field first to give a plain message, and shows the module's own message for anything else.
import { SAMPLES } from "./samples.js";

const $ = (id) => document.getElementById(id);

const LIMIT_BYTES = 1048576; // pasted input over 1 MiB of UTF-8 is refused before wasm is called
const MAX_ROWS = 500; // line and cluster rows rendered; the JSON block always has everything
const MAX_JSON_CHARS = 200000;
const MAX_ISSUES_SHOWN = 8; // per line
const HEATMAP_CLUSTER_CAP = 20000; // clusters drawn in the heatmap; the JSON block always has everything

const GATE_THRESHOLD_MAX = 1000000;
const GATE_VERDICTS = { pass: "Pass", hold: "Hold", not_scored: "Not scored" }; // fixed set: nothing from the text names a verdict

let validateCalls = 0;
let gateCalls = 0;

// --- Browser requirements: feature detection at load, not a static list -----------------------
const REQUIREMENTS = {
  wasm: () => typeof WebAssembly === "object" && typeof WebAssembly.instantiate === "function",
  modules: () => "noModule" in HTMLScriptElement.prototype,
  // Optional: without them the demo still validates pasted text, and the file input is disabled.
  file: () => typeof File === "function" && typeof Blob.prototype.arrayBuffer === "function",
  utf8: () => {
    new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
    return true;
  },
};

function renderRequirements() {
  let ok = true;
  let filesOk = true;
  for (const li of document.querySelectorAll("#requirements-list li[data-req]")) {
    let pass = false;
    try {
      pass = Boolean(REQUIREMENTS[li.getAttribute("data-req")]());
    } catch {
      pass = false;
    }
    const mark = li.querySelector(".mark");
    mark.textContent = pass ? "✓" : "✗";
    mark.setAttribute("class", `mark ${pass ? "ok" : "bad"}`);
    mark.setAttribute("aria-label", pass ? "available" : "missing");
    if (li.getAttribute("data-optional") === "true") filesOk = filesOk && pass;
    else ok = ok && pass;
  }
  return { ok, filesOk };
}

function showLoadError(message) {
  $("load-error-text").textContent = message;
  $("load-error").hidden = false;
}

// --- Small helpers ----------------------------------------------------------------------------
function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.setAttribute("class", className);
  if (text !== undefined) node.textContent = text;
  return node;
}

// Four decimals by integer arithmetic: truncated, never rounded. 704762 -> "0.7047".
function fmt4(ppm) {
  const whole = Math.floor(ppm / 1000000);
  const frac = Math.floor((ppm % 1000000) / 100);
  return `${whole}.${String(frac).padStart(4, "0")}`;
}

function fmtInt(n) {
  return n.toLocaleString("en-US");
}

// Show invisible, control and private-use code points as visible placeholders so a defect in the
// text can be seen in the table. Everything else is shown as it is.
function visible(s) {
  let out = "";
  for (const ch of s) {
    const cp = ch.codePointAt(0);
    const invisible =
      cp < 0x20 ||
      (cp >= 0x7f && cp <= 0x9f) ||
      (cp >= 0x200b && cp <= 0x200f) ||
      (cp >= 0x202a && cp <= 0x202e) ||
      (cp >= 0x2066 && cp <= 0x2069) ||
      cp === 0xfeff ||
      (cp >= 0xe000 && cp <= 0xf8ff) ||
      (cp >= 0xe0000 && cp <= 0xe0fff) || // tag characters and variation selectors supplement
      cp >= 0xf0000;
    if (!invisible) out += ch;
    else if (cp === 0x200d) out += "⟨ZWJ⟩";
    else if (cp === 0x200c) out += "⟨ZWNJ⟩";
    else if (cp === 0xfeff) out += "⟨BOM⟩";
    else out += `⟨U+${cp.toString(16).toUpperCase().padStart(4, "0")}⟩`;
  }
  return out;
}

function td(className, text) {
  return el("td", className, text);
}

// --- Build line -------------------------------------------------------------------------------
// The build id (Sprint 5): "Built from main at <sha12>" for a CI build, "Local build <sha12>[-dirty]" for a local one, "Local build"
// when the build had no git checkout. A commit shows as its first 12 hex digits only when it is a full 40-hex SHA.
let buildLabel = "Local build";
let buildCommit = "";
let buildModule = "";
async function loadBuild() {
  try {
    const res = await fetch(new URL("./build.json", import.meta.url));
    if (!res.ok) throw new Error(`build.json: HTTP ${res.status}`);
    const build = await res.json();
    const commit = typeof build.sha === "string" && /^[0-9a-f]{40}$/.test(build.sha) ? build.sha.slice(0, 12) : "";
    if (build.source === "ci" && commit) {
      buildLabel = "Built from main at ";
      buildCommit = commit;
    } else {
      buildLabel = "Local build";
      buildCommit = commit ? `${commit}${build.dirty === true ? "-dirty" : ""}` : "";
    }
    buildModule = typeof build.id === "string" ? build.id : "unknown";
  } catch {
    buildLabel = "Local build";
    buildCommit = "";
    buildModule = "unknown";
  }
  $("module-id").textContent = buildModule;
}

function renderBuildLine(spec) {
  const code = (t) => el("code", "", t);
  const first = buildLabel.endsWith(" ") ? [buildLabel, code(buildCommit), " by .github/workflows/pages.yml"] : [buildLabel, " ", code(buildCommit || "no git checkout")];
  $("build-line").replaceChildren(...first, " · report ", code(spec));
}

// --- Rendering --------------------------------------------------------------------------------
function clearResults(g) {
  $("score-value").textContent = "—";
  $("score-meter").value = 0;
  $("score-detail").textContent = "";
  $("line-rows").replaceChildren();
  $("line-count").textContent = "";
  $("lines-note").hidden = true;
  $("cluster-rows").replaceChildren();
  $("cluster-count").textContent = "";
  $("clusters-note").hidden = true;
  $("json-out").textContent = "";
  $("json-note").hidden = true;
  $("heatmap-rows").replaceChildren();
  $("heatmap-count").textContent = "";
  $("heatmap-note").hidden = true;
  renderRules(g, null);
  clearGate("The gate was not run for this input.");
}

function renderRules(g, report) {
  const kinds = JSON.parse(g.issue_kinds());
  const weights = report ? report.score.weights : null;
  const counts = report ? report.summary.by_kind : {};
  const frag = document.createDocumentFragment();
  for (const name of kinds) {
    const li = el("li", counts[name] ? "fired" : "");
    li.setAttribute("data-kind", name);
    li.setAttribute("data-count", String(counts[name] ?? 0));
    li.append(name);
    const detail = el("span", "state");
    detail.textContent = report ? ` — weight ${weights[name]}, fired ${counts[name] ?? 0}` : "";
    li.append(detail);
    frag.append(li);
  }
  $("issue-kinds").replaceChildren(frag);
}

function issueItem(issue, cluster) {
  const li = el("li");
  li.append(el("code", "kind", issue.kind), ` · cluster ${issue.cluster} `);
  li.append(el("span", "cluster-text", `«${visible(cluster.text)}»`));
  if (issue.code_point) li.append(` · ${issue.code_point}`);
  return li;
}

// --- Heatmap ----------------------------------------------------------------------------------
// Severity of a cluster is the sum of the weights of the rules that fired on it (report.score.weights);
// a line's bucket is the same sum over the line's clusters. Buckets: clean 0, low 1..399, mid 400..799,
// high 800 and above. Class names come from this fixed set only; titles and aria-labels are rule names
// from issue_kinds(); no attribute is built from the text.
function bucketOf(sum) {
  if (sum <= 0) return "clean";
  if (sum < 400) return "low";
  if (sum < 800) return "mid";
  return "high";
}

function renderHeatmap(g, report) {
  const known = new Set(JSON.parse(g.issue_kinds()));
  const weights = report.score.weights;
  const severity = new Map();
  const names = new Map();
  for (const issue of report.issues) {
    if (!known.has(issue.kind)) continue;
    severity.set(issue.cluster, (severity.get(issue.cluster) ?? 0) + (weights[issue.kind] ?? 0));
    if (!names.has(issue.cluster)) names.set(issue.cluster, []);
    if (!names.get(issue.cluster).includes(issue.kind)) names.get(issue.cluster).push(issue.kind);
  }
  const frag = document.createDocumentFragment();
  let drawn = 0;
  let lines = 0;
  for (const line of report.lines) {
    if (drawn >= HEATMAP_CLUSTER_CAP) break;
    let lineSum = 0;
    for (let c = line.cluster_start; c < line.cluster_end; c += 1) lineSum += severity.get(c) ?? 0;
    const lineBucket = bucketOf(lineSum);
    const row = el("div", "hm-line");
    row.append(el("span", "hm-no", String(line.index + 1)));
    const strip = el("span", `strip sev-${lineBucket}`);
    strip.setAttribute("role", "img");
    strip.setAttribute("aria-label", `line ${line.index + 1}: ${lineBucket}`);
    strip.setAttribute("data-line", String(line.index));
    row.append(strip);
    const textBox = el("span", "hm-text");
    // The line terminator is an allowed control and never flagged; it is not drawn.
    const last = report.clusters[line.cluster_end - 1];
    const end = last && /^(\r\n|\n|\r)$/.test(last.text) ? line.cluster_end - 1 : line.cluster_end;
    for (let c = line.cluster_start; c < end && drawn < HEATMAP_CLUSTER_CAP; c += 1) {
      const sum = severity.get(c) ?? 0;
      const span = el("span", `cl sev-${bucketOf(sum)}`, visible(report.clusters[c].text));
      span.setAttribute("data-cluster", String(c));
      if (sum > 0) {
        const label = names.get(c).join(", ");
        span.setAttribute("role", "mark");
        span.setAttribute("title", label);
        span.setAttribute("aria-label", label);
      }
      textBox.append(span);
      drawn += 1;
    }
    row.append(textBox);
    frag.append(row);
    lines += 1;
  }
  $("heatmap-rows").replaceChildren(frag);
  const total = report.clusters.length;
  $("heatmap-count").textContent = `${fmtInt(lines)} of ${fmtInt(report.lines.length)} line${report.lines.length === 1 ? "" : "s"}`;
  const note = $("heatmap-note");
  if (drawn >= HEATMAP_CLUSTER_CAP && lines < report.lines.length) {
    note.textContent = `The heatmap shows the first ${fmtInt(HEATMAP_CLUSTER_CAP)} of ${fmtInt(total)} clusters (${fmtInt(lines)} of ${fmtInt(report.lines.length)} lines); the line table, the rule counts and the JSON report cover everything.`;
    note.hidden = false;
  } else {
    note.hidden = true;
  }
}

function renderLines(report) {
  const rows = $("line-rows");
  const frag = document.createDocumentFragment();
  const shown = Math.min(report.lines.length, MAX_ROWS);
  let issueAt = 0;
  for (let i = 0; i < shown; i += 1) {
    const line = report.lines[i];
    // The line's clusters, minus its terminator, as text.
    const parts = [];
    for (let c = line.cluster_start; c < line.cluster_end; c += 1) parts.push(report.clusters[c].text);
    let lineText = parts.join("");
    lineText = lineText.replace(/(\r\n|\n|\r)$/, "");
    const chars = Array.from(visible(lineText));
    const clipped = chars.length > 60 ? `${chars.slice(0, 60).join("")}…` : chars.join("");

    // Issues are in cluster order, so one forward pass assigns them to lines.
    const mine = [];
    while (issueAt < report.issues.length && report.issues[issueAt].cluster < line.cluster_end) {
      mine.push(report.issues[issueAt]);
      issueAt += 1;
    }

    const tr = el("tr", line.flagged_clusters > 0 ? "flagged" : "");
    tr.append(
      td("idx", String(line.index + 1)),
      td("line-text", clipped),
      td("num", String(line.cluster_end - line.cluster_start)),
      td("num", String(line.flagged_clusters)),
      td("num line-score", fmt4(line.score_ppm)),
    );
    const cell = td("issues");
    if (mine.length === 0) {
      cell.textContent = "none";
    } else {
      const ul = el("ul", "issue-list");
      for (const issue of mine.slice(0, MAX_ISSUES_SHOWN)) ul.append(issueItem(issue, report.clusters[issue.cluster]));
      if (mine.length > MAX_ISSUES_SHOWN) ul.append(el("li", "more", `+ ${mine.length - MAX_ISSUES_SHOWN} more`));
      cell.append(ul);
    }
    tr.append(cell);
    frag.append(tr);
  }
  rows.replaceChildren(frag);
  const n = report.lines.length;
  $("line-count").textContent = `${n} line${n === 1 ? "" : "s"}`;
  const note = $("lines-note");
  if (n > shown) {
    note.textContent = `Showing the first ${fmtInt(shown)} of ${fmtInt(n)} lines; the JSON report has all of them.`;
    note.hidden = false;
  } else {
    note.hidden = true;
  }
}

function renderClusters(report) {
  const byCluster = new Map();
  for (const issue of report.issues) {
    if (!byCluster.has(issue.cluster)) byCluster.set(issue.cluster, []);
    byCluster.get(issue.cluster).push(issue.kind);
  }
  const shown = Math.min(report.clusters.length, MAX_ROWS);
  const frag = document.createDocumentFragment();
  for (let i = 0; i < shown; i += 1) {
    const c = report.clusters[i];
    const kinds = byCluster.get(i);
    const tr = el("tr", kinds ? "flagged" : "");
    tr.append(
      td("idx", String(c.index)),
      td("cluster", visible(c.text)),
      td("cp", c.code_points.join(" ")),
      td("bytes", `${c.start}–${c.end}`),
      td("rules", kinds ? [...new Set(kinds)].join(", ") : ""),
    );
    frag.append(tr);
  }
  $("cluster-rows").replaceChildren(frag);
  const n = report.clusters.length;
  $("cluster-count").textContent = `${fmtInt(n)} cluster${n === 1 ? "" : "s"}`;
  const note = $("clusters-note");
  if (n > shown) {
    note.textContent = `Showing the first ${fmtInt(shown)} of ${fmtInt(n)} clusters.`;
    note.hidden = false;
  } else {
    note.hidden = true;
  }
}

function renderJson(json) {
  $("json-out").textContent = json.length > MAX_JSON_CHARS ? json.slice(0, MAX_JSON_CHARS) : json;
  const note = $("json-note");
  if (json.length > MAX_JSON_CHARS) {
    note.textContent = `Truncated: showing the first ${fmtInt(MAX_JSON_CHARS)} of ${fmtInt(json.length)} characters. The CLI prints all of it.`;
    note.hidden = false;
  } else {
    note.hidden = true;
  }
}

function render(g, text) {
  const json = g.validate(text);
  validateCalls += 1;
  $("call-count").textContent = String(validateCalls);
  const report = JSON.parse(json);
  $("score-value").textContent = fmt4(report.score.ppm);
  $("score-meter").value = report.score.ppm;
  const s = report.summary;
  $("score-detail").textContent =
    `score_ppm ${report.score.ppm} · penalty ${report.score.penalty} · ${fmtInt(s.flagged_clusters)} of ${fmtInt(s.cluster_count)} clusters flagged · ${fmtInt(s.issue_count)} issues in ${fmtInt(report.lines.length)} lines`;
  renderHeatmap(g, report);
  renderLines(report);
  renderClusters(report);
  renderRules(g, report);
  renderJson(json);
}

// --- The Gate tab -----------------------------------------------------------------------------
function setGateNote(message) {
  const note = $("gate-note");
  note.textContent = message;
  note.hidden = message === "";
}

// Empty the verdict, the details and the JSON (never leave a stale answer next to a new input), with an optional note.
function clearGate(message = "") {
  const verdict = $("gate-verdict");
  verdict.textContent = "—";
  verdict.setAttribute("data-verdict", "");
  $("gate-details").replaceChildren();
  $("gate-json").textContent = "";
  setGateNote(message);
}

// Two decimals of a percentage by integer arithmetic, truncated: 666666 -> "66.66".
function fmtPercent(ppm) {
  const whole = Math.floor(ppm / 10000);
  const frac = Math.floor((ppm % 10000) / 100);
  return `${whole}.${String(frac).padStart(2, "0")}`;
}

// The threshold field: a whole number from 0 to 1,000,000, digits only. Returns the number, or null with a note.
function readGateThreshold() {
  const raw = $("gate-threshold").value.trim();
  if (!/^[0-9]{1,7}$/.test(raw) || Number(raw) > GATE_THRESHOLD_MAX) {
    return null;
  }
  return Number(raw);
}

function renderGate(g, text) {
  const threshold = readGateThreshold();
  if (threshold === null) {
    clearGate("The threshold must be a whole number from 0 to 1,000,000 (parts per million), digits only. The gate was not run.");
    return;
  }
  let json;
  try {
    json = g.gate(text, threshold);
  } catch (err) {
    clearGate(`The gate refused this input: ${err instanceof Error ? err.message : String(err)}. It was not run.`);
    return;
  }
  gateCalls += 1;
  $("gate-call-count").textContent = String(gateCalls);
  const report = JSON.parse(json);
  const verdict = $("gate-verdict");
  verdict.textContent = GATE_VERDICTS[report.verdict] ?? "—";
  verdict.setAttribute("data-verdict", GATE_VERDICTS[report.verdict] ? report.verdict : "");
  const rows = [
    ["Script", report.script],
    ["Devanagari share", `devanagari_ppm ${report.devanagari_ppm} (${fmtPercent(report.devanagari_ppm)}% of the letters, truncated)`],
    ["Score", report.scored ? `ppm ${report.ppm} (${fmt4(report.ppm)})` : "not scored (ppm null): not mostly Devanagari, passed through unjudged"],
    ["Threshold", `threshold_ppm ${report.threshold_ppm}`],
  ];
  const frag = document.createDocumentFragment();
  for (const [name, value] of rows) {
    frag.append(el("dt", "", name), el("dd", "", value));
  }
  $("gate-details").replaceChildren(frag);
  $("gate-json").textContent = json;
  setGateNote("");
}

// Tabs: Report and Gate. Roving tabindex, arrow keys move between them; the hidden attribute shows one panel.
function selectTab(name) {
  for (const tab of ["report", "gate"]) {
    const on = tab === name;
    const button = $(`tab-${tab}`);
    button.setAttribute("aria-selected", on ? "true" : "false");
    button.setAttribute("tabindex", on ? "0" : "-1");
    $(`panel-${tab}`).hidden = !on;
  }
}

// --- Input, the size limit and wiring ---------------------------------------------------------
function inputBytes(text) {
  // A UTF-16 unit is at least one UTF-8 byte, so a longer string is certainly over the limit and
  // need not be encoded.
  if (text.length > LIMIT_BYTES) return { bytes: text.length, atLeast: true };
  return { bytes: new TextEncoder().encode(text).length, atLeast: false };
}

async function main() {
  const { ok, filesOk } = renderRequirements();
  await loadBuild();
  if (!ok) {
    renderBuildLine("unavailable");
    showLoadError(
      "This browser lacks WebAssembly or ES modules, so the glyphsift module cannot run here. Nothing else on the page depends on it.",
    );
    return;
  }

  let g;
  try {
    g = await import("./pkg/glyphsift.js");
    await g.default({ module_or_path: new URL("./pkg/glyphsift_bg.wasm", import.meta.url) });
  } catch (err) {
    renderBuildLine("unavailable");
    showLoadError(`The module failed to load: ${err instanceof Error ? err.message : String(err)}`);
    return;
  }

  $("report-spec").textContent = g.report_spec();
  renderBuildLine(g.report_spec());

  const textarea = $("text");
  const sampleNotice = $("sample-notice");
  const inputNote = $("input-note");
  const fileNote = $("file-note");
  const fileInput = $("file-input");
  const dropZone = $("drop-zone");

  // The text the Gate tab last ran on, or null when the input was refused or empty of a result.
  let gateText = null;

  // Validate exactly `text` (the textarea's value, or a decoded file) and show the result, or refuse it.
  const validateText = (text) => {
    const { bytes, atLeast } = inputBytes(text);
    $("byte-count").textContent = `${atLeast ? "at least " : ""}${fmtInt(bytes)} of ${fmtInt(LIMIT_BYTES)} bytes`;
    if (bytes > LIMIT_BYTES) {
      // Refused before the validator is called.
      inputNote.textContent =
        `Refused: this text is ${atLeast ? "at least " : ""}${fmtInt(bytes)} bytes of UTF-8 and the demo accepts at most ${fmtInt(LIMIT_BYTES)} bytes (1 MiB). ` +
        "Nothing was sent anywhere and the validator was not run.";
      inputNote.hidden = false;
      gateText = null;
      clearResults(g);
      return;
    }
    inputNote.textContent = "";
    inputNote.hidden = true;
    try {
      render(g, text);
    } catch (err) {
      inputNote.textContent = `The validator refused this text: ${err instanceof Error ? err.message : String(err)}`;
      inputNote.hidden = false;
      gateText = null;
      clearResults(g);
      return;
    }
    gateText = text;
    renderGate(g, text);
  };
  const update = () => validateText(textarea.value);

  textarea.addEventListener("input", () => {
    // Hand-typed or edited text: the sample and file notices no longer apply.
    sampleNotice.hidden = true;
    fileNote.hidden = true;
    update();
  });

  // The tabs.
  for (const name of ["report", "gate"]) {
    $(`tab-${name}`).addEventListener("click", () => selectTab(name));
    $(`tab-${name}`).addEventListener("keydown", (ev) => {
      if (ev.key !== "ArrowLeft" && ev.key !== "ArrowRight") return;
      ev.preventDefault();
      const next = name === "report" ? "gate" : "report";
      selectTab(next);
      $(`tab-${next}`).focus();
    });
  }
  // The threshold field: judge the same text again at the new threshold (or say why the threshold is refused).
  $("gate-threshold").addEventListener("input", () => {
    if (gateText === null) {
      if (readGateThreshold() === null) {
        clearGate("The threshold must be a whole number from 0 to 1,000,000 (parts per million), digits only. The gate was not run.");
      } else if ($("gate-note").textContent.startsWith("The threshold must")) {
        clearGate("The gate was not run for this input.");
      }
      return;
    }
    renderGate(g, gateText);
  });

  $("samples").addEventListener("click", (ev) => {
    const button = ev.target.closest("button[data-sample]");
    if (!button) return;
    const sample = SAMPLES[button.getAttribute("data-sample")];
    if (!sample) return;
    textarea.value = sample.text;
    sampleNotice.textContent = sample.note;
    sampleNotice.hidden = false;
    fileNote.hidden = true;
    update();
  });

  // --- Local files: the drop zone and the picker --------------------------------------------------
  const refuseFile = (message) => {
    sampleNotice.hidden = true;
    fileNote.hidden = true;
    inputNote.textContent = message;
    inputNote.hidden = false;
    gateText = null;
    clearResults(g);
  };
  let loadSeq = 0;
  const loadFile = async (file, extraFiles) => {
    loadSeq += 1;
    const mine = loadSeq;
    // The size is checked on the File object first: an oversized file is never read or decoded.
    if (file.size > LIMIT_BYTES) {
      $("byte-count").textContent = `${fmtInt(file.size)} of ${fmtInt(LIMIT_BYTES)} bytes`;
      refuseFile(
        `This file is over 1 MiB (${fmtInt(file.size)} bytes; the demo accepts at most ${fmtInt(LIMIT_BYTES)}). ` +
          "Nothing was uploaded, the file was not read and the validator was not run.",
      );
      return;
    }
    let buffer;
    try {
      buffer = await file.arrayBuffer();
    } catch {
      if (mine === loadSeq) refuseFile("This file could not be read. Nothing was uploaded and the validator was not run.");
      return;
    }
    if (mine !== loadSeq) return; // a newer file replaced this one while it was being read
    let text;
    try {
      // Fatal: any invalid byte sequence is an error. ignoreBOM keeps a BOM in the text, as the CLI does.
      text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(buffer);
    } catch {
      refuseFile("This file is not valid UTF-8 text. Nothing was uploaded and the validator was not run.");
      return;
    }
    sampleNotice.hidden = true;
    textarea.value = text;
    const name = Array.from(file.name).slice(0, 80).join("");
    fileNote.textContent =
      `Loaded ${name} (${fmtInt(file.size)} bytes), read in this tab only.` +
      (extraFiles > 0 ? ` ${extraFiles} more file${extraFiles === 1 ? " was" : "s were"} dropped; only the first file is read.` : "");
    fileNote.hidden = false;
    validateText(text);
  };

  if (filesOk) {
    fileInput.addEventListener("change", () => {
      const file = fileInput.files && fileInput.files[0];
      const extra = fileInput.files ? fileInput.files.length - 1 : 0;
      if (file) loadFile(file, extra);
      // Allow the same file to be chosen again later.
      fileInput.value = "";
    });
    const hasFiles = (ev) => ev.dataTransfer && Array.from(ev.dataTransfer.types || []).includes("Files");
    for (const type of ["dragenter", "dragover"]) {
      dropZone.addEventListener(type, (ev) => {
        if (!hasFiles(ev)) return;
        ev.preventDefault();
        ev.dataTransfer.dropEffect = "copy";
        dropZone.classList.add("dragging");
      });
    }
    dropZone.addEventListener("dragleave", () => dropZone.classList.remove("dragging"));
    dropZone.addEventListener("drop", (ev) => {
      if (!hasFiles(ev)) return;
      ev.preventDefault();
      dropZone.classList.remove("dragging");
      const files = ev.dataTransfer.files;
      if (files && files.length > 0) loadFile(files[0], files.length - 1);
    });
    // A file dropped anywhere else must not make the browser navigate to it and leave the demo.
    for (const type of ["dragover", "drop"]) {
      window.addEventListener(type, (ev) => {
        if (!hasFiles(ev)) return;
        ev.preventDefault();
        if (ev.type === "dragover" && ev.dataTransfer) ev.dataTransfer.dropEffect = "none";
      });
    }
  } else {
    fileInput.disabled = true;
    fileNote.textContent = "Reading local files is not available in this browser; paste the text instead.";
    fileNote.hidden = false;
  }

  textarea.value = SAMPLES.clean.text;
  sampleNotice.textContent = SAMPLES.clean.note;
  sampleNotice.hidden = false;
  update();
  document.body.dataset.ready = "true";
}

main();
