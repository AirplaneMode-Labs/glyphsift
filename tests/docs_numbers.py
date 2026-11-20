#!/usr/bin/env python3
"""D3-03: every number on docs/what-glyphsift-measures.md is re-read from the committed file it cites.

    python3 -I tests/docs_numbers.py

The page is the only text the outreach drafts may quote, so a figure on it must be a figure in a committed file. This test
recomputes each one (standard library only; no network, no build) from:

  docs/score-vs-noise.csv                  the benchmark rows
  crates/glyphsift-core/src/gate.rs        DEFAULT_GATE_THRESHOLD_PPM
  crates/glyphsift-core/src/report.rs      the IssueKind variants (the rule count)
  tests/determinism/gate/{cases,expected}.jsonl and tests/determinism/samples/   the determinism corpus

and requires the exact formatted string to appear on the page (thousands separators as the page writes them). Change a value in
the CSV and the recomputed string is no longer on the page, so the test fails. It also pins the wording limits the page must
keep and the words it must never contain (no partner, person, employer, compliance or cost claim).
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


def check(ok, what):
    global FAILS
    print(("ok   - " if ok else "FAIL - ") + what)
    if not ok:
        FAILS += 1


def n(v):
    return f"{v:,}"


def main():
    if not os.path.isfile(PAGE):
        check(False, "docs/what-glyphsift-measures.md exists")
        return 1
    with open(PAGE, encoding="utf-8") as f:
        page = f.read()
    check(True, "docs/what-glyphsift-measures.md exists")

    def cited(s, what):
        check(s in page, f"the page states {what}: {s!r}")

    # --- the benchmark CSV ---
    with open(os.path.join(ROOT, "docs", "score-vs-noise.csv"), newline="", encoding="utf-8") as f:
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
    with open(os.path.join(ROOT, "docs", "score-vs-noise.csv"), "rb") as f:
        csv_bytes = f.read()
    check(b"\r" not in csv_bytes, "the committed benchmark CSV is LF only (so its bytes, and the figures read from it, are the same on every checkout)")

    # --- the commands the page must name so a reader can regenerate every figure ---
    for cmd in (
        "glyphsift bench --verify docs/score-vs-noise.csv",
        "glyphsift bench --corpus bench/corpus/clean.txt --seeds 1,2,3 --csv docs/score-vs-noise.csv --svg docs/score-vs-noise.svg",
        "scripts/determinism.sh",
        "python3 -I tests/docs_numbers.py",
    ):
        check(cmd in page, f"the page names the command {cmd!r}")
    for f_ in ("docs/score-vs-noise.csv", "docs/gate.md", "tests/determinism/gate/expected.jsonl", "crates/glyphsift-core/src/gate.rs"):
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

    print(f"docs numbers: {FAILS} failed")
    return 0 if FAILS == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
