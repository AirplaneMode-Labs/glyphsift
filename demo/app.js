// glyphsift demo. Everything runs in this tab: the WASM module is loaded from ./pkg/, the text never
// leaves the page, and the only network requests are for this page's own files.
//
// Every string that comes from the report, from a sample or from the pasted text reaches the page
// through textContent or createTextNode, never as markup (scripts/check-demo-sources.sh enforces it).
import { SAMPLES } from "./samples.js";

const $ = (id) => document.getElementById(id);

const LIMIT_BYTES = 1048576; // pasted input over 1 MiB of UTF-8 is refused before wasm is called
const MAX_ROWS = 500; // line and cluster rows rendered; the JSON block always has everything
const MAX_JSON_CHARS = 200000;
const MAX_ISSUES_SHOWN = 8; // per line

let validateCalls = 0;

// --- Browser requirements: feature detection at load, not a static list -----------------------
const REQUIREMENTS = {
  wasm: () => typeof WebAssembly === "object" && typeof WebAssembly.instantiate === "function",
  modules: () => "noModule" in HTMLScriptElement.prototype,
};

function renderRequirements() {
  let ok = true;
  for (const li of document.querySelectorAll("#requirements-list li[data-req]")) {
    let pass = false;
    try {
      pass = Boolean(REQUIREMENTS[li.dataset.req]());
    } catch {
      pass = false;
    }
    const mark = li.querySelector(".mark");
    mark.textContent = pass ? "✓" : "✗";
    mark.className = `mark ${pass ? "ok" : "bad"}`;
    mark.setAttribute("aria-label", pass ? "available" : "missing");
    ok = ok && pass;
  }
  return ok;
}

function showLoadError(message) {
  $("load-error-text").textContent = message;
  $("load-error").hidden = false;
}

// --- Small helpers ----------------------------------------------------------------------------
function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
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
let buildId = "local";
let buildSha = "";
async function loadBuild() {
  try {
    const res = await fetch(new URL("./build.json", import.meta.url));
    if (!res.ok) throw new Error(`build.json: HTTP ${res.status}`);
    const build = await res.json();
    // A commit shows as its first 12 hex digits only when it is a full 40-hex SHA; anything else is "local".
    buildId = typeof build.sha === "string" && /^[0-9a-f]{40}$/.test(build.sha) ? build.sha.slice(0, 12) : "local";
    buildSha = typeof build.id === "string" ? build.id : "unknown";
  } catch {
    buildId = "local";
    buildSha = "unknown";
  }
  $("module-id").textContent = buildSha;
}

function renderBuildLine(spec) {
  const code = (t) => el("code", "", t);
  $("build-line").replaceChildren(
    "Built from main at ",
    code(buildId),
    " by .github/workflows/pages.yml · report ",
    code(spec),
  );
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
  renderRules(g, null);
}

function renderRules(g, report) {
  const kinds = JSON.parse(g.issue_kinds());
  const weights = report ? report.score.weights : null;
  const counts = report ? report.summary.by_kind : {};
  const frag = document.createDocumentFragment();
  for (const name of kinds) {
    const li = el("li", counts[name] ? "fired" : "");
    li.dataset.kind = name;
    li.dataset.count = String(counts[name] ?? 0);
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
  renderLines(report);
  renderClusters(report);
  renderRules(g, report);
  renderJson(json);
}

// --- Input, the size limit and wiring ---------------------------------------------------------
function inputBytes(text) {
  // A UTF-16 unit is at least one UTF-8 byte, so a longer string is certainly over the limit and
  // need not be encoded.
  if (text.length > LIMIT_BYTES) return { bytes: text.length, atLeast: true };
  return { bytes: new TextEncoder().encode(text).length, atLeast: false };
}

async function main() {
  const ok = renderRequirements();
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

  const update = () => {
    const text = textarea.value;
    const { bytes, atLeast } = inputBytes(text);
    $("byte-count").textContent = `${atLeast ? "at least " : ""}${fmtInt(bytes)} of ${fmtInt(LIMIT_BYTES)} bytes`;
    if (bytes > LIMIT_BYTES) {
      // Refused before the validator is called.
      inputNote.textContent =
        `Refused: this text is ${atLeast ? "at least " : ""}${fmtInt(bytes)} bytes of UTF-8 and the demo accepts at most ${fmtInt(LIMIT_BYTES)} bytes (1 MiB). ` +
        "Nothing was sent anywhere and the validator was not run.";
      inputNote.hidden = false;
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
      clearResults(g);
    }
  };

  textarea.addEventListener("input", () => {
    // Hand-typed or edited text: the sample notice no longer applies.
    sampleNotice.hidden = true;
    update();
  });

  $("samples").addEventListener("click", (ev) => {
    const button = ev.target.closest("button[data-sample]");
    if (!button) return;
    const sample = SAMPLES[button.dataset.sample];
    if (!sample) return;
    textarea.value = sample.text;
    sampleNotice.textContent = sample.note;
    sampleNotice.hidden = false;
    update();
  });

  textarea.value = SAMPLES.clean.text;
  sampleNotice.textContent = SAMPLES.clean.note;
  sampleNotice.hidden = false;
  update();
  document.body.dataset.ready = "true";
}

main();
