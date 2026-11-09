//! The score-versus-noise benchmark: run the corruption generator over a clean corpus at the p
//! schedule, score every result, write the CSV, and check the monotonicity criterion.
//!
//! Criterion (the benchmark exits 1 on any violation):
//!
//! - (a) the mixed-family mean score, over the seeds, falls strictly at every consecutive step of
//!   the schedule from p = 0 to p = 0.4;
//! - (b) the mixed family is non-increasing in p for each seed;
//! - (c) every triggering family is non-increasing in p for each seed;
//! - (d) `score_ppm` is 1_000_000 at p = 0 for every row.
//!
//! "Triggering" is `Family::strength() == Strength::Triggering`; the seven none-directly families
//! are reported but not gated. Everything is integer arithmetic.

use std::collections::BTreeMap;
use std::fmt::Write as _;

use glyphsift_core::corrupt::{Family, SCHEDULE, SCHEDULE_PPM, Selection, Strength, corrupt};
use glyphsift_core::validate;

pub const CSV_HEADER: &str = "family,p,seed,cluster_count,flagged_clusters,score_ppm,recall_ppm";

/// One `(selection, p, seed)` measurement.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Row {
    pub family: String,
    /// The p label from the schedule (`0`, `0.01`, ...).
    pub p: String,
    pub seed: u64,
    pub cluster_count: u64,
    pub flagged_clusters: u64,
    pub score_ppm: u64,
    /// Share of declared sites whose expected rule fired, in ppm; `None` when no site declared one.
    pub recall_ppm: Option<u64>,
}

/// Every selection the benchmark runs: the 19 families in table order, then `mixed`.
pub fn selections() -> Vec<Selection> {
    let mut v: Vec<Selection> = Family::ALL.iter().map(|&f| Selection::Family(f)).collect();
    v.push(Selection::Mixed);
    v
}

/// Run the benchmark over `corpus` for `seeds`.
pub fn run(corpus: &str, seeds: &[u64]) -> Result<Vec<Row>, String> {
    let mut rows = Vec::with_capacity(20 * SCHEDULE.len() * seeds.len());
    for selection in selections() {
        for (label, ppm) in SCHEDULE.iter().zip(SCHEDULE_PPM) {
            for &seed in seeds {
                let corrupted = corrupt(corpus, selection, ppm, seed);
                let report = validate(&corrupted.text).map_err(|e| e.to_string())?;
                let (mut declared, mut hit) = (0u64, 0u64);
                for site in corrupted.sites.iter().filter(|s| !s.kinds.is_empty()) {
                    declared += 1;
                    if report
                        .issues
                        .iter()
                        .any(|i| i.cluster == site.cluster && site.kinds.contains(&i.kind))
                    {
                        hit += 1;
                    }
                }
                rows.push(Row {
                    family: selection.name().to_owned(),
                    p: (*label).to_owned(),
                    seed,
                    cluster_count: report.summary.cluster_count as u64,
                    flagged_clusters: report.summary.flagged_clusters as u64,
                    score_ppm: u64::from(report.score.ppm),
                    recall_ppm: (declared > 0).then(|| hit * 1_000_000 / declared),
                });
            }
        }
    }
    Ok(rows)
}

/// The CSV text: header, then one line per row, LF line endings.
pub fn to_csv(rows: &[Row]) -> String {
    let mut out = String::from(CSV_HEADER);
    out.push('\n');
    for r in rows {
        let recall = r.recall_ppm.map(|v| v.to_string()).unwrap_or_default();
        let _ = writeln!(
            out,
            "{},{},{},{},{},{},{}",
            r.family, r.p, r.seed, r.cluster_count, r.flagged_clusters, r.score_ppm, recall
        );
    }
    out
}

/// Read a CSV written by [`to_csv`].
pub fn parse_csv(text: &str) -> Result<Vec<Row>, String> {
    let mut lines = text.lines();
    if lines.next() != Some(CSV_HEADER) {
        return Err(format!("the first line must be {CSV_HEADER:?}"));
    }
    let mut rows = Vec::new();
    for (n, line) in lines.enumerate() {
        let at = n + 2;
        let f: Vec<&str> = line.split(',').collect();
        if f.len() != 7 {
            return Err(format!("line {at}: expected 7 fields, found {}", f.len()));
        }
        let num = |s: &str, what: &str| {
            s.parse::<u64>()
                .map_err(|_| format!("line {at}: {what} {s:?} is not a non-negative integer"))
        };
        if !SCHEDULE.contains(&f[1]) {
            return Err(format!("line {at}: p {:?} is not on the schedule", f[1]));
        }
        if Selection::from_name(f[0]).is_none() {
            return Err(format!("line {at}: unknown family {:?}", f[0]));
        }
        rows.push(Row {
            family: f[0].to_owned(),
            p: f[1].to_owned(),
            seed: num(f[2], "seed")?,
            cluster_count: num(f[3], "cluster_count")?,
            flagged_clusters: num(f[4], "flagged_clusters")?,
            score_ppm: num(f[5], "score_ppm")?,
            recall_ppm: if f[6].is_empty() {
                None
            } else {
                Some(num(f[6], "recall_ppm")?)
            },
        });
    }
    Ok(rows)
}

/// Scores of one `(family, seed)` along the schedule.
type Series = [Option<u64>; 7];

/// Index the rows as `(family, seed) -> series`, refusing duplicates.
fn index(rows: &[Row]) -> Result<BTreeMap<(String, u64), Series>, Vec<String>> {
    let mut map: BTreeMap<(String, u64), Series> = BTreeMap::new();
    let mut problems = Vec::new();
    for r in rows {
        let Some(k) = SCHEDULE.iter().position(|p| *p == r.p) else {
            continue;
        };
        let slot = &mut map.entry((r.family.clone(), r.seed)).or_insert([None; 7])[k];
        if slot.replace(r.score_ppm).is_some() {
            problems.push(format!(
                "(incomplete) {} seed {} p={} appears twice",
                r.family, r.seed, r.p
            ));
        }
    }
    if problems.is_empty() {
        Ok(map)
    } else {
        Err(problems)
    }
}

/// The result of checking the criterion.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Verdict {
    /// One line per violation, each starting with the criterion letter.
    pub violations: Vec<String>,
    /// Per criterion: `(letter, description, violated)`.
    pub checked: Vec<(char, String, bool)>,
}

impl Verdict {
    pub fn pass(&self) -> bool {
        self.violations.is_empty()
    }
}

/// Check criteria (a) to (d) on `rows`.
pub fn verdict(rows: &[Row]) -> Verdict {
    let mut v = Verdict::default();
    let map = match index(rows) {
        Ok(m) => m,
        Err(problems) => {
            v.violations = problems;
            return v;
        }
    };
    let mut seeds: Vec<u64> = map
        .keys()
        .filter(|(f, _)| f == "mixed")
        .map(|&(_, s)| s)
        .collect();
    seeds.sort_unstable();
    if seeds.is_empty() {
        v.violations
            .push("(incomplete) there are no rows for the mixed family".to_owned());
        return v;
    }
    // Every selection must be present for every seed with all seven schedule points.
    for selection in selections() {
        for &seed in &seeds {
            match map.get(&(selection.name().to_owned(), seed)) {
                Some(s) if s.iter().all(Option::is_some) => {}
                _ => v.violations.push(format!(
                    "(incomplete) {} seed {seed} is missing schedule points",
                    selection.name()
                )),
            }
        }
    }
    if !v.violations.is_empty() {
        return v;
    }
    let series = |family: &str, seed: u64| -> Vec<u64> {
        map[&(family.to_owned(), seed)]
            .iter()
            .map(|s| s.unwrap_or(0))
            .collect()
    };

    // (a) the mean over the seeds falls strictly: compare sums, the seed count being the same.
    let before = v.violations.len();
    let sums: Vec<u64> = (0..SCHEDULE.len())
        .map(|k| seeds.iter().map(|&s| series("mixed", s)[k]).sum())
        .collect();
    for k in 0..SCHEDULE.len() - 1 {
        if sums[k + 1] >= sums[k] {
            v.violations.push(format!(
                "(a) the mixed mean does not fall strictly from p={} to p={} (sum over seeds {} -> {})",
                SCHEDULE[k],
                SCHEDULE[k + 1],
                sums[k],
                sums[k + 1]
            ));
        }
    }
    v.checked.push((
        'a',
        "the mixed-family mean score falls strictly at every step".to_owned(),
        v.violations.len() > before,
    ));

    // (b) mixed, per seed.
    let before = v.violations.len();
    for &seed in &seeds {
        non_increasing(
            "(b)",
            "mixed",
            seed,
            &series("mixed", seed),
            &mut v.violations,
        );
    }
    v.checked.push((
        'b',
        "mixed is non-increasing in p for each seed".to_owned(),
        v.violations.len() > before,
    ));

    // (c) every triggering family, per seed.
    let before = v.violations.len();
    let mut gated = 0;
    for family in Family::ALL
        .iter()
        .filter(|f| f.strength() == Strength::Triggering)
    {
        gated += 1;
        for &seed in &seeds {
            non_increasing(
                "(c)",
                family.name(),
                seed,
                &series(family.name(), seed),
                &mut v.violations,
            );
        }
    }
    v.checked.push((
        'c',
        format!("each of the {gated} triggering families is non-increasing in p for each seed"),
        v.violations.len() > before,
    ));

    // (d) the clean corpus scores 1_000_000 everywhere.
    let before = v.violations.len();
    for r in rows
        .iter()
        .filter(|r| r.p == "0" && r.score_ppm != 1_000_000)
    {
        v.violations.push(format!(
            "(d) {} seed {} scores {} at p=0, not 1000000",
            r.family, r.seed, r.score_ppm
        ));
    }
    v.checked.push((
        'd',
        "score_ppm is 1000000 at p=0 for every row".to_owned(),
        v.violations.len() > before,
    ));
    v
}

fn non_increasing(letter: &str, family: &str, seed: u64, s: &[u64], out: &mut Vec<String>) {
    for k in 0..s.len() - 1 {
        if s[k + 1] > s[k] {
            out.push(format!(
                "{letter} {family} seed {seed}: score rises from {} at p={} to {} at p={}",
                s[k],
                SCHEDULE[k],
                s[k + 1],
                SCHEDULE[k + 1]
            ));
        }
    }
}

/// The text printed after a run or a `--verify`.
pub fn verdict_text(v: &Verdict, rows: usize) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "bench: {rows} rows");
    for (letter, what, violated) in &v.checked {
        let _ = writeln!(
            out,
            "({letter}) {what}: {}",
            if *violated { "VIOLATED" } else { "ok" }
        );
    }
    for line in &v.violations {
        let _ = writeln!(out, "violation: {line}");
    }
    let _ = writeln!(out, "verdict: {}", if v.pass() { "PASS" } else { "FAIL" });
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rows_from(f: impl Fn(&str, usize, u64) -> u64) -> Vec<Row> {
        let mut rows = Vec::new();
        for s in selections() {
            for (k, p) in SCHEDULE.iter().enumerate() {
                for seed in 1..=3u64 {
                    rows.push(Row {
                        family: s.name().to_owned(),
                        p: (*p).to_owned(),
                        seed,
                        cluster_count: 1000,
                        flagged_clusters: 0,
                        score_ppm: f(s.name(), k, seed),
                        recall_ppm: None,
                    });
                }
            }
        }
        rows
    }

    #[test]
    fn a_strictly_falling_everything_passes() {
        let rows = rows_from(|_, k, _| 1_000_000 - 10_000 * k as u64);
        assert!(verdict(&rows).pass());
    }

    #[test]
    fn an_injected_non_monotone_series_is_a_violation() {
        let rows = rows_from(|f, k, seed| {
            let base = 1_000_000 - 10_000 * k as u64;
            if f == "control_leak" && seed == 3 && k == 4 {
                base + 10_001
            } else {
                base
            }
        });
        let v = verdict(&rows);
        assert!(!v.pass());
        assert!(
            v.violations
                .iter()
                .any(|l| l.starts_with("(c) control_leak seed 3"))
        );
    }

    #[test]
    fn a_none_directly_wobble_is_not_gated() {
        let rows = rows_from(|f, k, _| {
            let base = 1_000_000 - 10_000 * k as u64;
            if f == "ocr_confusion" && k == 6 {
                1_000_000
            } else {
                base
            }
        });
        assert!(verdict(&rows).pass());
    }

    #[test]
    fn a_flat_mixed_mean_violates_a() {
        let rows = rows_from(|f, k, _| {
            if f == "mixed" && k >= 5 {
                900_000
            } else {
                1_000_000 - 10_000 * k as u64
            }
        });
        let v = verdict(&rows);
        assert!(v.violations.iter().any(|l| l.starts_with("(a)")));
    }

    #[test]
    fn csv_round_trips() {
        let rows = rows_from(|_, k, seed| 1_000_000 - 10_000 * k as u64 - seed);
        let back = parse_csv(&to_csv(&rows)).unwrap();
        assert_eq!(back, rows);
        assert!(parse_csv("bad\n").is_err());
    }
}
