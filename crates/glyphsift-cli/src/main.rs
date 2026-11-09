//! `glyphsift` command-line front end. A thin wrapper over `glyphsift-core`.
//!
//! Exit codes: 0 report written; 2 input error (unreadable file, invalid UTF-8); 3 the validator
//! is not implemented yet (Sprint 1), in which case a JSON error object is printed to stdout.

use std::io::{Read, Write};
use std::process::ExitCode;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(
    name = "glyphsift",
    version,
    about = "Is extracted Indic text clean enough to trust?"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Validate the UTF-8 text in FILE (or stdin when FILE is `-`) and print the canonical JSON
    /// report.
    Check {
        /// Path to a UTF-8 text file, or `-` for standard input.
        file: String,
    },
}

fn read_input(file: &str) -> Result<String, String> {
    let mut bytes = Vec::new();
    if file == "-" {
        std::io::stdin()
            .read_to_end(&mut bytes)
            .map_err(|e| format!("cannot read stdin: {e}"))?;
    } else {
        bytes = std::fs::read(file).map_err(|e| format!("cannot read {file}: {e}"))?;
    }
    String::from_utf8(bytes).map_err(|e| format!("{file}: input is not valid UTF-8: {e}"))
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match cli.command {
        Command::Check { file } => {
            let text = match read_input(&file) {
                Ok(t) => t,
                Err(msg) => {
                    eprintln!("error: {msg}");
                    return ExitCode::from(2);
                }
            };
            let mut out = std::io::stdout().lock();
            match glyphsift_core::validate(&text) {
                Ok(report) => {
                    let _ = writeln!(out, "{}", glyphsift_core::to_canonical_json(&report));
                    ExitCode::SUCCESS
                }
                Err(glyphsift_core::Error::Unimplemented { since }) => {
                    let body = serde_json::json!({ "error": "unimplemented", "since": since });
                    let _ = writeln!(out, "{body}");
                    ExitCode::from(3)
                }
            }
        }
    }
}
