// glyphsift demo. Everything runs in this tab: the WASM module is loaded from ./pkg/, the text never
// leaves the page, and the only network requests are for this page's own files.
import { SAMPLES } from "./samples.js";

const $ = (id) => document.getElementById(id);

// --- Browser requirements: feature detection at load, not a static list -----------------------
const REQUIREMENTS = {
  wasm: () => typeof WebAssembly === "object" && typeof WebAssembly.instantiate === "function",
  modules: () => "noModule" in HTMLScriptElement.prototype,
};

function renderRequirements() {
  let ok = true;
  for (const li of document.querySelectorAll("#requirements-list li[data-req]")) {
    const key = li.dataset.req;
    let pass = false;
    try {
      pass = Boolean(REQUIREMENTS[key]());
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

// --- Build line -------------------------------------------------------------------------------
async function renderBuild() {
  try {
    const res = await fetch(new URL("./build.json", import.meta.url));
    if (!res.ok) throw new Error(`build.json: HTTP ${res.status}`);
    const build = await res.json();
    const sha = typeof build.sha === "string" ? build.sha.slice(0, 12) : "unknown";
    $("build-line").replaceChildren(
      "Built from main at ",
      Object.assign(document.createElement("code"), { textContent: sha }),
      " by .github/workflows/pages.yml",
    );
    $("module-id").textContent = typeof build.id === "string" ? build.id : "unknown";
  } catch (err) {
    $("build-line").textContent = `Build information unavailable (${err.message})`;
    $("module-id").textContent = "unknown";
  }
}

// --- Rendering --------------------------------------------------------------------------------
function td(className, text) {
  const cell = document.createElement("td");
  if (className) cell.className = className;
  cell.textContent = text;
  return cell;
}

function renderClusters(g, text) {
  const rows = JSON.parse(g.clusters_json(text));
  const tbody = $("cluster-rows");
  const frag = document.createDocumentFragment();
  for (const c of rows) {
    const tr = document.createElement("tr");
    tr.append(
      td("idx", String(c.index)),
      td("cluster", c.text),
      td("cp", c.code_points.join(" ")),
      td("bytes", `${c.start}–${c.end}`),
    );
    frag.append(tr);
  }
  tbody.replaceChildren(frag);
  const n = rows.length;
  $("cluster-count").textContent = `${n} cluster${n === 1 ? "" : "s"}`;
}

// What the CLI prints for the same input (exit code 3). `since` is read from the thrown message,
// "... (lands in Sprint 2)", so the two stay in step.
function cliEquivalent(message) {
  const m = /lands in ([^)]+)\)/.exec(message);
  return JSON.stringify({ error: "unimplemented", since: m ? m[1] : "Sprint 2" });
}

function renderValidate(g, text) {
  let out;
  try {
    const report = g.validate(text);
    out = `validate() returned a report:\n${report}`;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    out = `thrown: ${message}\nCLI equivalent (exit code 3): ${cliEquivalent(message)}`;
  }
  $("validate-out").textContent = out;
}

function renderIssueKinds(g) {
  const kinds = JSON.parse(g.issue_kinds());
  const frag = document.createDocumentFragment();
  for (const name of kinds) {
    const li = document.createElement("li");
    const state = document.createElement("span");
    state.className = "state";
    state.textContent = " — not yet checked";
    li.append(name, state);
    frag.append(li);
  }
  $("issue-kinds").replaceChildren(frag);
}

// --- Wiring -----------------------------------------------------------------------------------
async function main() {
  renderBuild();
  const ok = renderRequirements();
  if (!ok) {
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
    showLoadError(`The module failed to load: ${err instanceof Error ? err.message : String(err)}`);
    return;
  }

  $("report-spec").textContent = g.report_spec();
  $("crate-version").textContent = g.version();
  renderIssueKinds(g);

  const textarea = $("text");
  const notice = $("sample-notice");

  const update = () => {
    const text = textarea.value;
    renderClusters(g, text);
    renderValidate(g, text);
  };

  textarea.addEventListener("input", () => {
    // Hand-typed or edited text: the sample notice no longer applies.
    notice.hidden = true;
    update();
  });

  $("samples").addEventListener("click", (ev) => {
    const button = ev.target.closest("button[data-sample]");
    if (!button) return;
    const sample = SAMPLES[button.dataset.sample];
    if (!sample) return;
    textarea.value = sample.text;
    notice.hidden = !sample.defect;
    update();
  });

  textarea.value = SAMPLES.clean.text;
  notice.hidden = true;
  update();
}

main();
