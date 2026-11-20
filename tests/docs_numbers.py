#!/usr/bin/env python3
"""D3-03: every number on docs/what-glyphsift-measures.md is re-read from the committed file it cites.

    python3 -I tests/docs_numbers.py

The page is the only text the outreach drafts may quote, so a figure on it must be a figure in a committed file. This test
recomputes each one (standard library only; no network, no build) from:

  docs/benchmarks/score-vs-noise.csv       the benchmark rows (the raw file; a byte-identical copy of docs/score-vs-noise.csv, checked here)
  crates/glyphsift-core/src/gate.rs        DEFAULT_GATE_THRESHOLD_PPM
  crates/glyphsift-core/src/report.rs      the IssueKind variants (the rule count)
  tests/determinism/gate/{cases,expected}.jsonl and tests/determinism/samples/   the determinism corpus

and requires the exact formatted string to appear on the page (thousands separators as the page writes them). Change a value in
the CSV and the recomputed string is no longer on the page, so the test fails. It also pins the wording limits the page must
keep and the words it must never contain (no partner, person, employer, compliance or cost claim).

Owner decision, 20 Nov 2026: every benchmark figure quoted in the README and in docs/ has a matching row in a raw file committed under
docs/benchmarks/ (index: docs/benchmarks/README.md). benchmark_claims() below re-reads those files and fails when
  - a row of a score table in the README (mixed mean, minimum and maximum; the twelve triggering families; the seven blind spots) differs
    from the one recomputed from docs/benchmarks/score-vs-noise.csv, or a row has no counterpart;
  - the README's recall statement, "599 of 807", "285 of 288" or the linearity ratio differ from docs/benchmarks/*.json;
  - a row of the two hold tables of docs/gate.md, or a count in the prose after them, differs from docs/benchmarks/gate-holds.json;
  - an `N ms` figure in the README, the CHANGELOG or docs/*.md matches no millisecond value of any docs/benchmarks/*.json, unless its
    paragraph says "raw data not kept".
Exit 0 when every check passes, 1 otherwise.
"""
import csv
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE = os.path.join(ROOT, "docs", "what-glyphsift-measures.md")
FAILS = 0


def check(ok, what, detail=""):
    global FAILS
    print(("ok   - " if ok else "FAIL - ") + what + (f" [{detail}]" if detail and not ok else ""))
    if not ok:
        FAILS += 1


def n(v):
    return f"{v:,}"


# ---------------------------------------------------------------------------------------------------------------------------
# Owner decision, 20 Nov 2026: every benchmark figure in the README and docs/ has a matching row in docs/benchmarks/.
# ---------------------------------------------------------------------------------------------------------------------------
BENCH = os.path.join(ROOT, "docs", "benchmarks")
NOT_8GB = "not measured on 8 GB"


def read_text(*parts):
    with open(os.path.join(ROOT, *parts), encoding="utf-8") as f:
        return f.read()


def read_json(name):
    with open(os.path.join(BENCH, name), encoding="utf-8") as f:
        return json.load(f)


def section(text, heading):
    """The lines of a '## heading' section, up to the next '## ' heading."""
    out, on = [], False
    for line in text.split("\n"):
        if line.startswith("## "):
            if on:
                break
            on = line == heading
            continue
        if on:
            out.append(line)
    return "\n".join(out)


def tables(text):
    """Every markdown table in text as a list of rows, each row a list of stripped cells (the separator row is dropped)."""
    out, cur = [], []
    for line in text.split("\n") + [""]:
        if line.lstrip().startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if all(set(c) <= set(":-") and c for c in cells):
                continue
            cur.append(cells)
        elif cur:
            out.append(cur)
            cur = []
    return out


def blocks(text):
    """Paragraph-like blocks: a blank line, a heading, a list item or a table row starts a new one."""
    out, cur = [], []
    for line in text.split("\n"):
        starts = line.lstrip().startswith(("- ", "* ", "#", "|")) or re.match(r"\s*\d+\. ", line) is not None
        if line.strip() == "" or starts:
            if cur:
                out.append("\n".join(cur))
            cur = [] if line.strip() == "" else [line]
        else:
            cur.append(line)
    if cur:
        out.append("\n".join(cur))
    return out


def r4(num, den):
    """num / den parts per million as the README's four-decimal score, rounded half up, in integers: 998302 is 0.9983."""
    v = (2 * num * 10000 + den * 1_000_000) // (2 * den * 1_000_000)
    return f"{v // 10000}.{v % 10000:04d}"


def ms_values(node, key=""):
    """Every millisecond value of a raw file: numbers under a key with the word ms in it (best_ms, runs_ms, bench_wall_clock_ms_runs, ...)."""
    vals = []
    words = key.split("_")
    if isinstance(node, dict):
        for k, v in node.items():
            vals += ms_values(v, k)
    elif isinstance(node, list):
        for v in node:
            vals += ms_values(v, key)
    elif isinstance(node, (int, float)) and not isinstance(node, bool) and "ms" in words:
        vals.append(float(node))
    return vals


def benchmark_claims(rows):
    print("== the README and docs/ figures against docs/benchmarks/")
    names = sorted(x for x in os.listdir(BENCH) if x.endswith(".json"))
    check(len(names) >= 7, f"docs/benchmarks/ holds the raw .json files ({len(names)} found)")
    raw = {x: read_json(x) for x in names}
    readme = read_text("README.md")
    bench = section(readme, "## Benchmarks")
    limits = section(readme, "## Limitations")

    # ---- the score tables: recomputed from the raw CSV, row by row, both ways ----
    ps = sorted({r["p"] for r in rows}, key=float)
    seeds = sorted({r["seed"] for r in rows})
    by = defaultdict(list)  # (family, p) -> [score_ppm per seed]
    for r in rows:
        by[(r["family"], r["p"])].append(int(r["score_ppm"]))
    flat = {f for f in {r["family"] for r in rows} if all(int(x["score_ppm"]) == 1_000_000 for x in rows if x["family"] == f)}
    triggering = sorted({r["family"] for r in rows} - flat - {"mixed"})
    check(len(triggering) == 12 and len(flat) == 7, f"the CSV has twelve triggering families and seven that never move the score ({len(triggering)}, {len(flat)})")
    mean_row = lambda fam, plist: [r4(sum(by[(fam, p)]), len(by[(fam, p)])) for p in plist]

    tabs = tables(bench)
    t1 = [t for t in tabs if t[0][0] == "Mixed family"]
    t2 = [t for t in tabs if t[0][0] == "Family" and t[0][1:3] == ["p=0.05", "p=0.4"]]
    check(len(t1) == 1 and len(t2) == 1, "the README Benchmarks section has the mixed table and the triggering-family table")
    if len(t1) == 1:
        want = {
            "mean of seeds 1 to 3": mean_row("mixed", ps),
            "minimum": [r4(min(by[("mixed", p)]), 1) for p in ps],
            "maximum": [r4(max(by[("mixed", p)]), 1) for p in ps],
        }
        check(t1[0][0][1:-1] == [f"p={p}" for p in ps], "the mixed table's columns are the CSV's noise levels")
        got = {row[0]: row[1:-1] for row in t1[0][1:]}
        check(sorted(got) == sorted(want), f"the mixed table has exactly the rows {sorted(want)} (found {sorted(got)})")
        for label, cells in want.items():
            check(got.get(label) == cells, f"README mixed row '{label}' equals the CSV: {cells}", f"README has {got.get(label)}")
    if len(t2) == 1:
        got = {row[0]: row[1:-1] for row in t2[0][1:]}
        check(sorted(got) == sorted(f"`{f}`" for f in triggering), "the family table has exactly the twelve triggering families of the CSV")
        for fam in triggering:
            want_cells = mean_row(fam, ["0.05", "0.4"])
            check(got.get(f"`{fam}`") == want_cells, f"README family row `{fam}` equals the CSV: {want_cells}", f"README has {got.get(f'`{fam}`')}")
    blind = [t for t in tables(limits) if t[0][0] == "Family" and t[0][1] == "p=0"]
    check(len(blind) == 1, "the README Limitations has the table of the seven blind-spot families")
    if blind:
        got = {row[0]: row[1:] for row in blind[0][1:]}
        check(sorted(got) == sorted(f"`{f}`" for f in flat), "the blind-spot table has exactly the families of the CSV whose score never moves")
        for fam in sorted(flat):
            check(got.get(f"`{fam}`") == mean_row(fam, ps), f"README blind-spot row `{fam}` equals the CSV (every step 1.0000)")

    # ---- the corpus: its line count and cluster count, as the README states them ----
    with open(os.path.join(ROOT, "bench", "corpus", "clean.txt"), encoding="utf-8") as f:
        corpus_lines = len(f.read().rstrip("\n").split("\n"))
    clusters0 = {int(r["cluster_count"]) for r in rows if r["p"] == "0"}
    check(len(clusters0) == 1, f"independent check: every p=0 row of the CSV has the same cluster count ({sorted(clusters0)})")
    check(f"the {corpus_lines}-line synthetic Hindi and Marathi corpus" in " ".join(bench.split()), f"the README says the corpus has {corpus_lines} lines (bench/corpus/clean.txt)")
    check(len(clusters0) == 1 and f"({next(iter(clusters0)):,} clusters, every line validating with zero issues)" in " ".join(bench.split()), "the README says the corpus has the CSV's cluster count, every line validating with zero issues")

    # ---- recall at p=0.05 ----
    declared = {r["family"] for r in rows if r["recall_ppm"] != ""}
    at05 = [r for r in rows if r["p"] == "0.05" and r["family"] in declared]
    check(all(r["recall_ppm"] in ("", "1000000") for r in at05), "independent check: recall at p=0.05 is 1,000,000 wherever a site declares a rule")
    check(sorted((r["family"], r["seed"]) for r in at05 if r["recall_ppm"] == "") == [("bindu_swap", "3")], "independent check: the only family and seed with no declared rule at p=0.05 is bindu_swap, seed 3")
    check("is 1.000000 for every family that declares a rule, in every seed that has one" in " ".join(bench.split()) and "seed 3 has none at p=0.05" in " ".join(bench.split()), "the README says recall is 1.000000 and names bindu_swap seed 3 (read from the CSV above)")

    # ---- the joiner counts ----
    js = raw.get("joiner-sites.json")
    if js is not None:
        flagged = {r["seed"]: int(r["flagged_clusters"]) for r in rows if r["family"] == "joiner_inject" and r["p"] == "0.05"}
        per_seed = js["data"]["seeds"]
        check({k: v["declared_sites"] for k, v in per_seed.items()} == flagged, f"the declared joiner sites per seed equal the CSV's flagged clusters for joiner_inject at p=0.05 {flagged}")
        total, decl = js["data"]["total_sites"], js["data"]["total_declared_sites"]
        check(total == sum(v["sites"] for v in per_seed.values()) and decl == sum(flagged.values()), "joiner-sites.json: the totals are the sums of the seeds, and the declared total is the CSV's flagged total")
        check(f"{decl} of {total} injected joiners at p=0.05 land in Devanagari clusters and are flagged" in " ".join(limits.split()), f"the README says '{decl} of {total} injected joiners at p=0.05 land in Devanagari clusters and are flagged'")
    else:
        check(False, "docs/benchmarks/joiner-sites.json exists")

    # ---- the linearity ratio ----
    wl = raw.get("wasm-linearity-m5pro-48gb.json")
    if wl is not None:
        d = wl["data"]
        check(d["ratio"] < d["limit"] and abs(d["ratio"] - d["ms_per_call_large"] / d["ms_per_call_small"]) <= 0.01, f"independent check: the stored ratio {d['ratio']} is the large per-call time over the small one and is under the limit {d['limit']}")
        check(f"takes {d['ratio']:.2f} times as long as a 2,500-mark run (linear is 2, quadratic 4;" in " ".join(readme.split()), f"the README says a 5,000-mark run takes {d['ratio']:.2f} times as long as a 2,500-mark run")
    else:
        check(False, "docs/benchmarks/wasm-linearity-m5pro-48gb.json exists")

    # ---- docs/gate.md: the hold tables and the prose counts ----
    gh = raw.get("gate-holds.json")
    gate_md = read_text("docs", "gate.md")
    if gh is not None:
        grows = gh["data"]["rows"]
        plabels = gh["data"]["p_levels"]
        check(plabels == ps, "gate-holds.json uses the CSV's noise levels")
        want_rows = []
        for r in grows:
            label = f"`{r['family']}`" if r["table"] == "by_family" else f"{r['lines_per_chunk']} line{'' if r['lines_per_chunk'] == 1 else 's'} ({r['chunks']:,} chunks)"
            want_rows.append("| " + " | ".join([label] + [str(h) for h in r["hold"]]) + " |")
        gate_lines = gate_md.split("\n")
        for row in want_rows:
            check(row in gate_lines, f"docs/gate.md has the hold row {row}")
        sec = section(gate_md, "## Which noise to use to produce a hold")
        hold_tables = [t for t in tables(sec)]
        in_doc = ["| " + " | ".join(row) + " |" for t in hold_tables for row in t[1:]]
        check(sorted(in_doc) == sorted(want_rows), f"docs/gate.md has exactly the {len(want_rows)} hold rows of gate-holds.json and no other (found {len(in_doc)})")
        for t in hold_tables:
            check(t[0][1:] == [f"p={p}" for p in plabels], f"a hold table of docs/gate.md has the noise levels of gate-holds.json as its columns ({t[0][0]})")
        hold = {(r["table"], r["family"], r["lines_per_chunk"]): dict(zip(plabels, r["hold"])) for r in grows}
        chunks = {(r["table"], r["family"], r["lines_per_chunk"]): r["chunks"] for r in grows}
        fam = lambda name, p: hold[("by_family", name, 3)][p]
        size = lambda lines, p: hold[("by_chunk_size", "mixed", lines)][p]
        pct = lambda h, c: int(100 * h / c + 0.5)
        flat_prose = " ".join(gate_md.split())
        check(fam("control_leak", "0.2") == 288 and fam("virama_insert", "0.4") == 288, "independent check: control_leak at p=0.2 and virama_insert at p=0.4 hold all 288 chunks")
        for frag in (
            f"Those hold {fam('control_leak', '0.1')} of 288 and {fam('virama_insert', '0.2')} of 288 chunks, and {fam('control_leak', '0.2')} of 288 one step higher",
            f"holds {fam('mixed', '0.4')} of 288 ({pct(fam('mixed', '0.4'), 288)}%)",
            f"(p=0.1: {size(1, '0.1')} of {chunks[('by_chunk_size', 'mixed', 1)]} one-line chunks, {pct(size(1, '0.1'), 864)}%, against {size(8, '0.1')} of {chunks[('by_chunk_size', 'mixed', 8)]} eight-line chunks, {pct(size(8, '0.1'), 108)}%)",
            f"(p=0.4: {size(1, '0.4')} of {chunks[('by_chunk_size', 'mixed', 1)]}, {pct(size(1, '0.4'), 864)}%, against {size(8, '0.4')} of {chunks[('by_chunk_size', 'mixed', 8)]}, {pct(size(8, '0.4'), 108)}%)",
        ):
            check(frag in flat_prose, f"docs/gate.md says '{frag}' (counts from gate-holds.json)")
        check(f"the gate holds `control_leak` at p=0.1 on {fam('control_leak', '0.1')} of 288 three-line chunks" in " ".join(readme.split()), f"the README says the gate holds `control_leak` at p=0.1 on {fam('control_leak', '0.1')} of 288 three-line chunks")
        check("docs/benchmarks/gate-holds.json" in gate_md, "docs/gate.md names docs/benchmarks/gate-holds.json")
    else:
        check(False, "docs/benchmarks/gate-holds.json exists")

    # ---- every `N ms` figure in the README, the CHANGELOG and docs/*.md is a millisecond value of a raw file, or its paragraph says raw data not kept ----
    allowed = set()
    for doc in raw.values():
        for v in ms_values(doc):
            allowed.add(round(v, 3))
            allowed.add(float(int(v + 0.5)))
    pattern = re.compile(r"(?<![A-Za-z0-9_.,])(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)? ?ms\b")
    files = ["README.md", "CHANGELOG.md", "CONTRIBUTING.md"] + [os.path.join("docs", x) for x in sorted(os.listdir(os.path.join(ROOT, "docs"))) if x.endswith(".md")] + [os.path.join("docs", "benchmarks", "README.md")]
    seen = unmatched = 0
    for rel in files:
        for block in blocks(read_text(*rel.split(os.sep))):
            for m in pattern.finditer(block):
                value = float(m.group(1).replace(",", "") + (m.group(2) or ""))
                seen += 1
                if value in allowed or "raw data not kept" in block.lower():
                    continue
                unmatched += 1
                check(False, f"{rel}: '{m.group(0)}' matches no millisecond value in docs/benchmarks/ and its paragraph does not say 'raw data not kept'", block.strip().split("\n")[0][:100])
    check(seen >= 10, f"the ms sweep found {seen} figures in the README, the CHANGELOG and docs/ (at least 10 expected)")
    check(unmatched == 0, "every ms figure in the README, the CHANGELOG and docs/ matches a raw file or is marked 'raw data not kept'")
    # the sweep must be able to fail: a made-up figure is not in the raw files
    check(pattern.search("it takes 61 ms") is not None and 61.0 not in allowed and "raw data not kept" not in "it takes 61 ms", "self-test: a quoted '61 ms' (a Sprint 3 figure with no raw file) would be refused")



def main():
    if not os.path.isfile(PAGE):
        check(False, "docs/what-glyphsift-measures.md exists")
        return 1
    with open(PAGE, encoding="utf-8") as f:
        page = f.read()
    check(True, "docs/what-glyphsift-measures.md exists")

    def cited(s, what):
        check(s in page, f"the page states {what}: {s!r}")

    # --- the benchmark CSV: the raw copy under docs/benchmarks/, which must be the committed docs/score-vs-noise.csv byte for byte ---
    with open(os.path.join(ROOT, "docs", "benchmarks", "score-vs-noise.csv"), "rb") as f:
        raw_csv_bytes = f.read()
    with open(os.path.join(ROOT, "docs", "score-vs-noise.csv"), "rb") as f:
        check(raw_csv_bytes == f.read(), "docs/benchmarks/score-vs-noise.csv is byte-identical to docs/score-vs-noise.csv")
    with open(os.path.join(ROOT, "docs", "benchmarks", "score-vs-noise.csv"), newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    ps = sorted({r["p"] for r in rows}, key=float)
    seeds = sorted({r["seed"] for r in rows})
    fams = sorted({r["family"] for r in rows})
    cited(f"{n(len(rows))} rows", "the CSV row count")
    cited(f"{len(fams)} noise families", "the family count")
    cited(f"{len(ps)} noise levels", "the noise level count")
    cited(f"{len(seeds)} seeds", "the seed count")
    cited("p=" + ", p=".join(ps), "the noise levels")

    by = defaultdict(dict)
    for r in rows:
        by[(r["family"], r["seed"])][float(r["p"])] = int(r["score_ppm"])
    decreasing = all(v[b] <= v[a] for v in by.values() for a, b in zip(sorted(v), sorted(v)[1:]))
    check(decreasing, "independent check: every (family, seed) series is non-increasing in p in the CSV")
    cited("0 of " + n(len(by)) + " (family, seed) series rise", "the count of series that rise")
    check(all(int(r["score_ppm"]) == 1_000_000 for r in rows if float(r["p"]) == 0), "independent check: score_ppm is 1,000,000 at p=0 in every row")

    mixed = defaultdict(list)
    for r in rows:
        if r["family"] == "mixed":
            mixed[r["p"]].append(int(r["score_ppm"]))
    for p in ps:
        cited(n(min(mixed[p])), f"the lowest mixed score at p={p}")
        cited(n(max(mixed[p])), f"the highest mixed score at p={p}")

    flat = sorted({r["family"] for r in rows if all(int(x["score_ppm"]) == 1_000_000 for x in rows if x["family"] == r["family"])})
    cited(f"{len(flat)} families never move the score", "the count of families whose score never moves")
    for fam in flat:
        cited(f"`{fam}`", f"the blind-spot family {fam}")

    # --- the rule count: one IssueKind variant per structural rule ---
    with open(os.path.join(ROOT, "crates", "glyphsift-core", "src", "report.rs"), encoding="utf-8") as f:
        src = f.read()
    body = src.split("pub enum IssueKind {", 1)[1].split("\n}", 1)[0]
    nrules = len(re.findall(r"^    [A-Z][A-Za-z0-9]*,\s*$", body, flags=re.M))
    cited(f"{nrules} structural rules", "the rule count (variants of IssueKind in report.rs)")

    # --- the gate threshold ---
    with open(os.path.join(ROOT, "crates", "glyphsift-core", "src", "gate.rs"), encoding="utf-8") as f:
        m = re.search(r"pub const DEFAULT_GATE_THRESHOLD_PPM: u32 = ([0-9_]+);", f.read())
    check(m is not None, "DEFAULT_GATE_THRESHOLD_PPM is declared in gate.rs")
    thr = int(m.group(1).replace("_", ""))
    cited(f"{thr} ppm", "the default gate threshold (as written in gate.rs, no separator)")
    worst_p01 = min(mixed["0.1"])
    best_p02 = max(mixed["0.2"])
    check(best_p02 < thr <= worst_p01, "independent check: the threshold lies in the gap between the worst mixed seed at p=0.1 and the best at p=0.2")
    cited(f"{n(worst_p01 - best_p02)} ppm", "the width of the gap")
    cited(f"{n(worst_p01 - thr)} ppm below", "the margin below the worst seed at p=0.1")
    cited(f"{n(thr - best_p02)} ppm above", "the margin above the best seed at p=0.2")

    # --- the determinism corpus ---
    gate_dir = os.path.join(ROOT, "tests", "determinism", "gate")
    with open(os.path.join(gate_dir, "cases.jsonl"), encoding="utf-8") as f:
        ncases = sum(1 for line in f if line.strip())
    tally = defaultdict(int)
    with open(os.path.join(gate_dir, "expected.jsonl"), encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            tally["rejected" if line == "rejected" else json.loads(line)["verdict"]] += 1
    check(sum(tally.values()) == ncases, "independent check: expected.jsonl has one line per case")
    samples = [x for x in os.listdir(os.path.join(ROOT, "tests", "determinism", "samples")) if x.endswith(".txt")]
    expected_reports = [x for x in os.listdir(os.path.join(ROOT, "tests", "determinism", "expected")) if x.endswith(".json")]
    check(len(samples) == len(expected_reports), "independent check: one expected report per sample")
    cited(f"{len(samples)} sample texts", "the sample count")
    cited(f"{ncases} gate cases", "the gate case count")
    for k in ("pass", "hold", "not_scored", "rejected"):
        cited(f"{tally[k]} {k}", f"the number of {k} cases")

    # --- Sprint 7: the page is in step with the version it describes and with the committed benchmark it quotes ---
    with open(os.path.join(ROOT, "Cargo.toml"), encoding="utf-8") as f:
        ws = re.search(r'^\[workspace\.package\][^\[]*?^version = "([^"]+)"', f.read(), flags=re.M | re.S)
    check(ws is not None, "Cargo.toml has a [workspace.package] version")
    status_line = next((l for l in page.splitlines() if l.startswith("Status:")), "")
    check(ws is not None and f"glyphsift {ws.group(1)}," in status_line, f"the page's Status line names glyphsift {ws.group(1) if ws else '?'} (the workspace version)")
    check("untagged and unpublished" in status_line, "the page's Status line says untagged and unpublished")
    check("Sprint 7" in status_line, "the page's Status line says it was re-read against the committed files in Sprint 7")
    csv_bytes = raw_csv_bytes
    check(b"\r" not in csv_bytes, "the committed benchmark CSV is LF only (so its bytes, and the figures read from it, are the same on every checkout)")

    # --- the commands the page must name so a reader can regenerate every figure ---
    for cmd in (
        "glyphsift bench --verify docs/score-vs-noise.csv",
        "glyphsift bench --corpus bench/corpus/clean.txt --seeds 1,2,3 --csv docs/score-vs-noise.csv --svg docs/score-vs-noise.svg",
        "scripts/determinism.sh",
        "python3 -I tests/docs_numbers.py",
    ):
        check(cmd in page, f"the page names the command {cmd!r}")
    for f_ in ("docs/score-vs-noise.csv", "docs/benchmarks/score-vs-noise.csv", "https://github.com/AirplaneMode-Labs/glyphsift/tree/main/docs/benchmarks", "docs/gate.md", "tests/determinism/gate/expected.jsonl", "crates/glyphsift-core/src/gate.rs"):
        check(f_ in page, f"the page cites the file {f_}")

    # --- limits, in the page's own words ---
    for s in ("Devanagari only", "unpublished", "not measured on 8 GB", "No claim about Hindi answer quality"):
        check(s in page, f"the page states the limit {s!r}")

    # --- words the page must never contain ---
    low = page.lower()
    for bad in ("sarvam", "ai4bharat", "employer", "compliance", "compliant", "cost saving", "cost-saving",
                "free ram", "gdpr", "dpdp", "rbi ", "regulat", "guarantee"):
        # "employer" may appear only in the sentence that disclaims it; allow it only inside the fixed limits sentence.
        if bad == "employer":
            check(low.count("employer") <= 1 and ("no reference to any employer" in low or low.count("employer") == 0), "the page names no employer (one disclaiming sentence at most)")
            continue
        check(bad not in low, f"the page does not contain {bad!r}")
    check(re.search(r"\b\d+(\.\d+)?\s*GB\b", page) is None or all("8 GB" in line for line in page.splitlines() if re.search(r"\b\d+(\.\d+)?\s*GB\b", line)),
          "the only GB figure on the page is the words 'not measured on 8 GB'")

    benchmark_claims(rows)

    print(f"docs numbers: {FAILS} failed")
    return 0 if FAILS == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
