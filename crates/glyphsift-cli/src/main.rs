//! `glyphsift` command-line front end. A thin wrapper over `glyphsift-core`.
//!
//! Commands:
//!
//! - `check FILE|-` validates UTF-8 text and prints the canonical JSON report.
//! - `corrupt` applies a seeded noise family to clean text (the OCR-corruption generator).
//! - `bench` runs the score-versus-noise benchmark and checks that the score falls as noise rises.
//!
//! Exit codes: 0 success; 1 I/O error, invalid UTF-8, input over the size limit, or (for `bench`)
//! a violated criterion; 2 usage error (bad or missing arguments); 4 `check --fail-under` and the
//! score is below the threshold. There is no exit code 3.

mod bench;
mod chart;

use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use glyphsift_core::corrupt::{Family, Selection, corrupt, parse_p_ppm, sites_json};
use glyphsift_core::{MAX_INPUT_BYTES, to_canonical_json, validate};

#[derive(Parser)]
#[command(
    name = "glyphsift",
    version,
    about = "Is extracted Indic text clean enough to trust?",
    after_help = "Exit codes: 0 success; 1 I/O or UTF-8 error (or a failed bench criterion); 2 usage error; 4 check --fail-under not met."
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Validate the UTF-8 text in FILE (or stdin when FILE is `-`) and print the canonical JSON
    /// report. Input is limited to 4 MiB.
    Check {
        /// Path to a UTF-8 text file, or `-` for standard input.
        file: String,
        /// Exit 4 (after printing the report) when the document score, in parts per million, is
        /// below this threshold.
        #[arg(long, value_name = "PPM", value_parser = clap::value_parser!(u32).range(0..=1_000_000))]
        fail_under: Option<u32>,
    },
    /// Corrupt clean text from stdin with a seeded noise family and print the result.
    Corrupt {
        /// A family name, or `mixed`; see --list-families.
        #[arg(long, required_unless_present = "list_families")]
        family: Option<String>,
        /// Probability as a decimal in [0, 1] with at most six decimals, for example 0.05.
        #[arg(
            long,
            required_unless_present = "list_families",
            allow_hyphen_values = true
        )]
        p: Option<String>,
        /// Seed (u64).
        #[arg(long, default_value_t = 1)]
        seed: u64,
        /// Write the sites sidecar (JSON) to this path.
        #[arg(long, value_name = "PATH")]
        sites: Option<PathBuf>,
        /// Print every family name, then `mixed`, and exit.
        #[arg(long)]
        list_families: bool,
    },
    /// Score the clean corpus corrupted at p in {0, 0.01, 0.02, 0.05, 0.1, 0.2, 0.4} for every
    /// family and `mixed`, write a CSV and an SVG, and exit 1 if the score does not fall as noise
    /// rises. With --verify, re-check an existing CSV instead.
    Bench {
        /// The clean corpus (UTF-8, one sentence per line).
        #[arg(
            long,
            value_name = "PATH",
            required_unless_present = "verify",
            conflicts_with = "verify"
        )]
        corpus: Option<PathBuf>,
        /// Comma-separated seeds, for example 1,2,3.
        #[arg(
            long,
            value_name = "LIST",
            required_unless_present = "verify",
            conflicts_with = "verify"
        )]
        seeds: Option<String>,
        /// Where to write the CSV.
        #[arg(
            long,
            value_name = "PATH",
            required_unless_present = "verify",
            conflicts_with = "verify"
        )]
        csv: Option<PathBuf>,
        /// Where to write the SVG chart.
        #[arg(
            long,
            value_name = "PATH",
            required_unless_present = "verify",
            conflicts_with = "verify"
        )]
        svg: Option<PathBuf>,
        /// Check the criterion on an existing CSV and exit 1 on any violation.
        #[arg(long, value_name = "CSV")]
        verify: Option<PathBuf>,
    },
}

const USAGE: u8 = 2;
const IO: u8 = 1;

/// Read at most `MAX_INPUT_BYTES` of UTF-8 from `file` (`-` is stdin).
fn read_input(file: &str) -> Result<String, String> {
    let limit = MAX_INPUT_BYTES as u64 + 1;
    let mut bytes = Vec::new();
    if file == "-" {
        std::io::stdin()
            .lock()
            .take(limit)
            .read_to_end(&mut bytes)
            .map_err(|e| format!("cannot read stdin: {e}"))?;
    } else {
        std::fs::File::open(file)
            .and_then(|f| f.take(limit).read_to_end(&mut bytes))
            .map_err(|e| format!("cannot read {file}: {e}"))?;
    }
    if bytes.len() > MAX_INPUT_BYTES {
        return Err(format!(
            "{file}: input is too large: it exceeds the limit of {MAX_INPUT_BYTES} bytes"
        ));
    }
    String::from_utf8(bytes).map_err(|e| format!("{file}: input is not valid UTF-8: {e}"))
}

fn fail(code: u8, msg: impl std::fmt::Display) -> ExitCode {
    eprintln!("error: {msg}");
    ExitCode::from(code)
}

fn check(file: &str, fail_under: Option<u32>) -> ExitCode {
    let text = match read_input(file) {
        Ok(t) => t,
        Err(msg) => return fail(IO, msg),
    };
    let report = match validate(&text) {
        Ok(r) => r,
        Err(e) => return fail(IO, e),
    };
    let mut out = std::io::stdout().lock();
    if writeln!(out, "{}", to_canonical_json(&report)).is_err() {
        return fail(IO, "cannot write to stdout");
    }
    match fail_under {
        Some(threshold) if report.score.ppm < threshold => {
            eprintln!(
                "error: score {} is below --fail-under {threshold}",
                report.score.ppm
            );
            ExitCode::from(4)
        }
        _ => ExitCode::SUCCESS,
    }
}

fn corrupt_cmd(
    family: Option<String>,
    p: Option<String>,
    seed: u64,
    sites: Option<PathBuf>,
    list_families: bool,
) -> ExitCode {
    if list_families {
        let mut out = std::io::stdout().lock();
        for f in Family::ALL {
            let _ = writeln!(out, "{}", f.name());
        }
        let _ = writeln!(out, "mixed");
        return ExitCode::SUCCESS;
    }
    // clap guarantees both are present when --list-families is absent.
    let (Some(family), Some(p)) = (family, p) else {
        return fail(USAGE, "--family and --p are required");
    };
    let Some(selection) = Selection::from_name(&family) else {
        return fail(
            USAGE,
            format!("unknown family {family:?}; see --list-families"),
        );
    };
    let ppm = match parse_p_ppm(&p) {
        Ok(v) => v,
        Err(e) => return fail(USAGE, e),
    };
    let text = match read_input("-") {
        Ok(t) => t,
        Err(msg) => return fail(IO, msg),
    };
    let corrupted = corrupt(&text, selection, ppm, seed);
    if let Some(path) = sites {
        let json = format!("{}\n", sites_json(selection, seed, ppm, &corrupted));
        if let Err(e) = std::fs::write(&path, json) {
            return fail(IO, format!("cannot write {}: {e}", path.display()));
        }
    }
    let mut out = std::io::stdout().lock();
    if out.write_all(corrupted.text.as_bytes()).is_err() {
        return fail(IO, "cannot write to stdout");
    }
    ExitCode::SUCCESS
}

fn parse_seeds(list: &str) -> Result<Vec<u64>, String> {
    let mut seeds = Vec::new();
    for part in list.split(',') {
        let seed: u64 = part
            .trim()
            .parse()
            .map_err(|_| format!("--seeds: {part:?} is not a u64"))?;
        if seeds.contains(&seed) {
            return Err(format!("--seeds: {seed} is listed twice"));
        }
        seeds.push(seed);
    }
    Ok(seeds)
}

fn write_file(path: &Path, contents: &str) -> Result<(), String> {
    std::fs::write(path, contents).map_err(|e| format!("cannot write {}: {e}", path.display()))
}

fn print_verdict(rows: &[bench::Row]) -> ExitCode {
    let v = bench::verdict(rows);
    let text = bench::verdict_text(&v, rows.len());
    let _ = std::io::stdout().lock().write_all(text.as_bytes());
    if v.pass() {
        ExitCode::SUCCESS
    } else {
        eprintln!(
            "error: {} violation(s) of the monotonicity criterion",
            v.violations.len()
        );
        ExitCode::from(IO)
    }
}

fn bench_cmd(
    corpus: Option<PathBuf>,
    seeds: Option<String>,
    csv: Option<PathBuf>,
    svg: Option<PathBuf>,
    verify: Option<PathBuf>,
) -> ExitCode {
    if let Some(path) = verify {
        let text = match std::fs::read_to_string(&path) {
            Ok(t) => t,
            Err(e) => return fail(IO, format!("cannot read {}: {e}", path.display())),
        };
        return match bench::parse_csv(&text) {
            Ok(rows) => print_verdict(&rows),
            Err(e) => fail(IO, format!("{}: {e}", path.display())),
        };
    }
    let (Some(corpus), Some(seeds), Some(csv), Some(svg)) = (corpus, seeds, csv, svg) else {
        return fail(USAGE, "--corpus, --seeds, --csv and --svg are required");
    };
    let seeds = match parse_seeds(&seeds) {
        Ok(s) => s,
        Err(e) => return fail(USAGE, e),
    };
    let text = match std::fs::read(&corpus)
        .map_err(|e| format!("cannot read {}: {e}", corpus.display()))
        .and_then(|b| {
            String::from_utf8(b).map_err(|e| format!("{}: not valid UTF-8: {e}", corpus.display()))
        }) {
        Ok(t) => t,
        Err(e) => return fail(IO, e),
    };
    let rows = match bench::run(&text, &seeds) {
        Ok(r) => r,
        Err(e) => return fail(IO, e),
    };
    if let Err(e) =
        write_file(&csv, &bench::to_csv(&rows)).and_then(|()| write_file(&svg, &chart::svg(&rows)))
    {
        return fail(IO, e);
    }
    print_verdict(&rows)
}

fn main() -> ExitCode {
    match Cli::parse().command {
        Command::Check { file, fail_under } => check(&file, fail_under),
        Command::Corrupt {
            family,
            p,
            seed,
            sites,
            list_families,
        } => corrupt_cmd(family, p, seed, sites, list_families),
        Command::Bench {
            corpus,
            seeds,
            csv,
            svg,
            verify,
        } => bench_cmd(corpus, seeds, csv, svg, verify),
    }
}
