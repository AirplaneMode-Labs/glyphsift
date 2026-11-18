//! How the gate behaves on noised chunks (Sprint 5, D3-01): the evidence behind docs/gate.md,
//! "Which noise to use to produce a hold". Needs the generator: `cargo test -p glyphsift-core --features corrupt`
//! (the workspace `cargo test` enables it through the CLI).
//!
//! The clean corpus `bench/corpus/clean.txt` (288 invented sentences, one per line) is corrupted as the benchmark does
//! (the whole text at once, seeds 1 to 3), split back into lines, and grouped into chunks of 1, 3 or 8 consecutive
//! lines, the sizes a pipeline cutting a page into pieces would produce. Each chunk goes through `gate` with the default
//! threshold. The tests pin what docs/gate.md says: nothing is held at p=0, holds only grow with p, no chunk of this
//! benchmark is ever "not scored", and the exact hold counts in the doc's two tables. Run with `--nocapture` to print
//! the rows.

use std::path::Path;

use glyphsift_core::corrupt::{Family, Selection, corrupt};
use glyphsift_core::{GateVerdict, gate};

/// The noise levels of the benchmark, in ppm.
const P_PPM: [u32; 7] = [0, 10_000, 20_000, 50_000, 100_000, 200_000, 400_000];

fn read(rel: &str) -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join(rel);
    std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
}

fn family(name: &str) -> Selection {
    Selection::from_name(name).unwrap_or_else(|| panic!("no family {name}"))
}

/// (pass, hold, not_scored) over every chunk of every seed 1 to 3.
fn tally(selection: Selection, p_ppm: u32, lines_per_chunk: usize) -> (u32, u32, u32) {
    let clean = read("../../bench/corpus/clean.txt");
    let (mut pass, mut hold, mut none) = (0, 0, 0);
    for seed in 1..=3u64 {
        let noised = corrupt(&clean, selection, p_ppm, seed).text;
        let lines: Vec<&str> = noised.lines().collect();
        for chunk in lines.chunks(lines_per_chunk) {
            match gate(&chunk.join("\n"), None).unwrap().verdict {
                GateVerdict::Pass => pass += 1,
                GateVerdict::Hold => hold += 1,
                GateVerdict::NotScored => none += 1,
            }
        }
    }
    (pass, hold, none)
}

const SELECTIONS: [&str; 7] = [
    "mixed",
    "matra_double",
    "virama_insert",
    "control_leak",
    "mixed_script",
    "matra_detach",
    "word_boundary",
];

#[test]
fn nothing_is_held_on_the_clean_corpus_holds_only_grow_with_noise_and_nothing_is_not_scored() {
    for name in SELECTIONS {
        for lines in [1usize, 3, 8] {
            let mut last = 0;
            for p in P_PPM {
                let (pass, hold, none) = tally(family(name), p, lines);
                assert_eq!(
                    none, 0,
                    "{name} p={p} {lines} lines: a noised chunk is not scored"
                );
                assert!(
                    hold >= last,
                    "{name} {lines} lines: holds fell from {last} to {hold} at p={p}"
                );
                if p == 0 {
                    assert_eq!(hold, 0, "{name} {lines} lines: a clean chunk was held");
                    assert!(pass > 0);
                }
                last = hold;
            }
        }
    }
}

/// Hold counts per noise level, as the cells of a markdown table row.
fn hold_cells(selection: Selection, lines: usize) -> String {
    P_PPM
        .iter()
        .map(|&p| tally(selection, p, lines).1.to_string())
        .collect::<Vec<_>>()
        .join(" | ")
}

/// The two tables of docs/gate.md ("Which noise to use to produce a hold") are these rows, nothing else.
#[test]
fn the_doc_tables_are_these_exact_hold_counts() {
    let doc =
        std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docs/gate.md"))
            .unwrap_or_default();
    let mut rows = Vec::new();
    // Table 1: 288 chunks of three lines (96 per seed, three seeds), five families.
    for name in [
        "mixed",
        "matra_double",
        "virama_insert",
        "control_leak",
        "mixed_script",
    ] {
        rows.push(format!("| `{name}` | {} |", hold_cells(family(name), 3)));
    }
    // Table 2: the mixed family by chunk size (864, 288 and 108 chunks).
    for (lines, total) in [(1usize, 864u32), (3, 288), (8, 108)] {
        rows.push(format!(
            "| {lines} line{} ({total} chunks) | {} |",
            if lines == 1 { "" } else { "s" },
            hold_cells(family("mixed"), lines)
        ));
    }
    for row in &rows {
        println!("{row}");
    }
    for row in &rows {
        assert!(
            doc.contains(row.as_str()),
            "docs/gate.md lacks the row {row:?}"
        );
    }
}

/// The recommendation in the doc: these settings hold (nearly) every three-line chunk, so D5's noised fixture is
/// held whatever the seed. The claim is checked here with a margin, not assumed.
#[test]
fn the_recommended_noise_holds_nearly_every_three_line_chunk() {
    let (pass, hold, none) = tally(family("control_leak"), 100_000, 3);
    assert_eq!(none, 0);
    assert!(
        hold * 100 >= (pass + hold) * 98,
        "control_leak p=0.1: {hold} held, {pass} passed"
    );
    let (pass, hold, none) = tally(family("virama_insert"), 200_000, 3);
    assert_eq!(none, 0);
    assert!(
        hold * 100 >= (pass + hold) * 99,
        "virama_insert p=0.2: {hold} held, {pass} passed"
    );
    // The mixed family at its top noise holds most three-line chunks but not all: a fixture must be checked.
    let (pass, hold, _) = tally(family("mixed"), 400_000, 3);
    assert!(
        hold * 100 >= (pass + hold) * 90 && pass > 0,
        "mixed p=0.4: {hold} held, {pass} passed"
    );
    // And the lowest noise barely holds anything at three lines.
    let (pass, hold, _) = tally(family("mixed"), 10_000, 3);
    assert!(
        pass * 100 >= (pass + hold) * 98,
        "mixed p=0.01: {hold} held, {pass} passed"
    );
    // Silence the unused import when the Family type is not otherwise named.
    let _ = Family::ALL.len();
}
