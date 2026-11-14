//! `glyphsift check` (D3-05), written before the command was reworked.
//!
//! Exit codes: 0 report printed and the score is not under the threshold; 1 I/O or UTF-8 error;
//! 2 usage error; 4 `--fail-under` and the score is below it. There is no exit code 3.

mod common;

use common::{run, scratch};
use glyphsift_core::{to_canonical_json, validate};

const CLEAN: &str = "नमस्ते।";
// Four clusters, one broken (unexpected_code_point): score 750_000.
const DAMAGED: &str = "कखग\u{FFFD}";

fn expected(text: &str) -> String {
    format!("{}\n", to_canonical_json(&validate(text).unwrap()))
}

#[test]
fn check_prints_the_canonical_json_report_from_stdin() {
    for text in [CLEAN, DAMAGED, "", "क\r\nख\n", "ोम काा ं नमस्ते िदुनिया"]
    {
        let r = run(&["check", "-"], text.as_bytes());
        assert_eq!(r.code, 0, "{text:?}: {}", r.stderr);
        assert_eq!(r.out(), expected(text), "{text:?}");
    }
}

#[test]
fn check_reads_a_file_and_reports_report_0_2() {
    let dir = scratch("check-file");
    let path = dir.join("sample.txt");
    std::fs::write(&path, DAMAGED).unwrap();
    let r = run(&["check", path.to_str().unwrap()], b"");
    assert_eq!(r.code, 0, "{}", r.stderr);
    assert_eq!(r.out(), expected(DAMAGED));
    let v: serde_json::Value = serde_json::from_str(&r.out()).unwrap();
    assert_eq!(v["spec"], "glyphsift.report/0.2");
    assert_eq!(v["score"]["ppm"], 750_000);
    assert_eq!(v["lines"].as_array().unwrap().len(), 1);
}

#[test]
fn fail_under_exits_4_when_the_score_is_below_the_threshold_and_still_prints_the_report() {
    let r = run(
        &["check", "-", "--fail-under", "800000"],
        DAMAGED.as_bytes(),
    );
    assert_eq!(r.code, 4);
    assert_eq!(
        r.out(),
        expected(DAMAGED),
        "the report is printed before exiting 4"
    );
    assert!(
        r.stderr.contains("750000"),
        "stderr names the score: {}",
        r.stderr
    );
    assert!(
        r.stderr.contains("800000"),
        "stderr names the threshold: {}",
        r.stderr
    );
}

#[test]
fn fail_under_passes_at_or_above_the_threshold() {
    for threshold in ["0", "750000", "1"] {
        let r = run(
            &["check", "-", "--fail-under", threshold],
            DAMAGED.as_bytes(),
        );
        assert_eq!(r.code, 0, "--fail-under {threshold}: {}", r.stderr);
    }
    let r = run(&["check", "-", "--fail-under", "1000000"], CLEAN.as_bytes());
    assert_eq!(r.code, 0, "a clean text scores exactly 1000000");
    let r = run(&["check", "-", "--fail-under", "1000000"], b"");
    assert_eq!(r.code, 0, "empty input scores 1000000");
    let r = run(
        &["check", "-", "--fail-under", "1000000"],
        DAMAGED.as_bytes(),
    );
    assert_eq!(r.code, 4);
}

#[test]
fn io_and_utf8_errors_exit_1() {
    let r = run(&["check", "/no/such/file.txt"], b"");
    assert_eq!(r.code, 1);
    assert!(r.stdout.is_empty());
    assert!(r.stderr.contains("/no/such/file.txt"), "{}", r.stderr);

    let r = run(&["check", "-"], b"\xff\xfe\xfd");
    assert_eq!(r.code, 1);
    assert!(r.stderr.contains("UTF-8"), "{}", r.stderr);
    assert!(r.stdout.is_empty());
}

#[test]
fn input_over_the_core_limit_exits_1() {
    let big = "क".repeat(glyphsift_core::MAX_INPUT_BYTES / 3 + 1);
    let r = run(&["check", "-"], big.as_bytes());
    assert_eq!(r.code, 1);
    assert!(r.stderr.contains("too large"), "{}", r.stderr);
}

#[test]
fn usage_errors_exit_2() {
    let cases: &[&[&str]] = &[
        &[],
        &["check"],
        &["check", "-", "--fail-under"],
        &["check", "-", "--fail-under", "abc"],
        &["check", "-", "--fail-under", "-5"],
        &["check", "-", "--fail-under", "1000001"],
        &["check", "-", "--fail-under", "1.5"],
        &["check", "-", "--bogus"],
        &["no-such-command"],
    ];
    for args in cases {
        let r = run(args, b"");
        assert_eq!(r.code, 2, "{args:?}: {}", r.stderr);
        assert!(r.stdout.is_empty(), "{args:?} printed to stdout");
    }
}

#[test]
fn there_is_no_exit_code_3_and_no_unimplemented_path() {
    for text in [CLEAN, DAMAGED, ""] {
        let r = run(&["check", "-"], text.as_bytes());
        assert_ne!(r.code, 3);
        assert!(!r.out().contains("unimplemented"));
    }
    let help = run(&["--help"], b"");
    assert!(!help.out().to_lowercase().contains("not implemented"));
}

// ---- Sprint 3 (D3-06): the documented surface of the command-line tool ---------------------------

fn repo_root() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

#[test]
fn version_prints_the_workspace_version_and_exits_0() {
    let r = run(&["--version"], b"");
    assert_eq!(r.code, 0, "{}", r.stderr);
    assert_eq!(
        r.out(),
        format!("glyphsift {}\n", env!("CARGO_PKG_VERSION"))
    );
    assert_eq!(env!("CARGO_PKG_VERSION"), "0.1.0");
}

#[test]
fn help_names_every_exit_code_and_every_command() {
    let r = run(&["--help"], b"");
    assert_eq!(r.code, 0, "{}", r.stderr);
    let help = r.out();
    for needle in [
        "check",
        "corrupt",
        "bench",
        "Exit codes:",
        "0 success",
        "1 I/O",
        "2 usage",
        "4 check",
    ] {
        assert!(help.contains(needle), "--help lacks {needle:?}:\n{help}");
    }
    for sub in ["check", "corrupt", "bench"] {
        let r = run(&[sub, "--help"], b"");
        assert_eq!(r.code, 0, "{sub} --help: {}", r.stderr);
    }
}

#[test]
fn a_directory_instead_of_a_file_exits_1() {
    let dir = scratch("check-dir");
    let r = run(&["check", dir.to_str().unwrap()], b"");
    assert_eq!(r.code, 1, "{}", r.stderr);
    assert!(r.stdout.is_empty());
}

#[test]
fn the_readme_cli_section_documents_the_commands_and_all_four_exit_codes() {
    let readme = std::fs::read_to_string(repo_root().join("README.md")).expect("README.md");
    let start = readme
        .find("\n### CLI")
        .expect("README has a '### CLI' section");
    let rest = &readme[start + 1..];
    // The section runs to the next heading of level 3 or 2.
    let end = rest[4..]
        .find("\n### ")
        .into_iter()
        .chain(rest[4..].find("\n## "))
        .min()
        .map_or(rest.len(), |i| i + 4);
    let section = &rest[..end];
    for needle in [
        "glyphsift check",
        "glyphsift corrupt",
        "glyphsift bench",
        "--fail-under",
        "--verify",
        "cargo install --path crates/glyphsift-cli --locked",
        "| 0 |",
        "| 1 |",
        "| 2 |",
        "| 4 |",
        "There is no exit code 3",
    ] {
        assert!(
            section.contains(needle),
            "the README CLI section lacks {needle:?}"
        );
    }
    // The whole README carries the honest sentence, and a registry install command appears only after
    // the "After the owner publishes" heading, never before it and never in prose elsewhere.
    assert!(readme.contains(
        "Not published yet: the npm scope @airplanemode and the PyPI and crates.io names are not reserved."
    ));
    let (before, after) = readme
        .split_once("### After the owner publishes")
        .expect("README has an 'After the owner publishes' block");
    for bare in [
        "cargo install glyphsift-cli",
        "pip install glyphsift",
        "npm i @airplanemode/glyphsift",
    ] {
        assert!(
            !before.contains(bare),
            "{bare:?} appears before the 'After the owner publishes' block"
        );
    }
    let block_end = after.find("\n## ").unwrap_or(after.len());
    for bare in [
        "cargo install glyphsift-cli",
        "pip install glyphsift",
        "npm i @airplanemode/glyphsift",
    ] {
        assert!(
            after[..block_end].contains(bare),
            "{bare:?} is missing from the block"
        );
        assert!(
            !after[block_end..].contains(bare),
            "{bare:?} appears again after the block"
        );
    }
}

#[test]
fn every_crate_ships_the_licence_and_notice_it_is_published_under() {
    let root = repo_root();
    for krate in [
        "glyphsift-core",
        "glyphsift-cli",
        "glyphsift-py",
        "glyphsift-wasm",
    ] {
        for file in ["LICENSE", "NOTICE"] {
            let copy = root.join("crates").join(krate).join(file);
            let want = std::fs::read(root.join(file)).expect("root licence file");
            let got =
                std::fs::read(&copy).unwrap_or_else(|_| panic!("crates/{krate}/{file} is missing"));
            assert_eq!(
                got, want,
                "crates/{krate}/{file} differs from the repository {file}"
            );
        }
    }
}

#[test]
fn the_cli_manifest_carries_the_crates_io_metadata() {
    let manifest = std::fs::read_to_string(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml"),
    )
    .expect("Cargo.toml");
    for needle in [
        "description = ",
        "license.workspace = true",
        "repository.workspace = true",
        "readme.workspace = true",
        "keywords.workspace = true",
        "categories.workspace = true",
        "rust-version.workspace = true",
        "name = \"glyphsift\"",
    ] {
        assert!(
            manifest.contains(needle),
            "crates/glyphsift-cli/Cargo.toml lacks {needle:?}"
        );
    }
}

#[test]
fn readmes_cite_no_scratch_paths_have_limitations_and_the_8_gb_column_reads_not_measured() {
    let root = repo_root();
    for path in [
        "README.md",
        "npm/README.md",
        "crates/glyphsift-py/README.md",
    ] {
        let text = std::fs::read_to_string(root.join(path)).unwrap_or_else(|_| panic!("{path}"));
        assert!(
            !text.contains("/private/tmp"),
            "{path} cites a scratch path"
        );
        assert!(
            text.lines().any(|l| l.starts_with("## Limitations")),
            "{path} has no Limitations section"
        );
        assert!(
            text.contains("release candidate, not tagged"),
            "{path} lacks 'release candidate, not tagged'"
        );
    }
    // Every table of the repository README that has a machine column has the 8 GB column. The throughput
    // table, the mixed-family table and the twelve-family table all read exactly "not measured" in every row.
    let readme = std::fs::read_to_string(root.join("README.md")).unwrap();
    let mut seen = 0;
    let mut nm = 0;
    let mut in_table = false;
    for line in readme.lines() {
        if line.starts_with('|') && line.contains("8 GB Windows no-GPU laptop") {
            in_table = true;
            seen += 1;
            continue;
        }
        if in_table {
            if !line.starts_with('|') {
                in_table = false;
                continue;
            }
            if line.starts_with("|---") {
                continue;
            }
            assert!(
                line.trim_end().ends_with("| not measured |"),
                "an 8 GB column cell does not read exactly 'not measured': {line}"
            );
            nm += 1;
        }
    }
    assert_eq!(
        seen, 3,
        "three benchmark tables carry the 8 GB column (mixed, twelve families, throughput)"
    );
    assert!(
        nm >= 3 + 12 + 5,
        "all rows of the three tables read 'not measured'"
    );
    // Every evidence path in the README names sprint 3 or the earlier sprint 2 run it supersedes.
    for line in readme.lines().filter(|l| l.contains("evidence/")) {
        assert!(
            line.contains("evidence/sprint-4/D3/")
                || line.contains("evidence/sprint-3/D3/")
                || line.contains("evidence/sprint-2/D3/"),
            "{line}"
        );
    }
}

/// Sprint 4 wording rules for the README (D3-04): the Status names Sprint 4, the benchmark machine is
/// named "Apple M5 Pro, 48 GB", the prose says "not measured on 8 GB", Tamil is the planned second script,
/// and Linux and Windows wheels are said to be built only by CI after the owner's push. The demo's not-yet
/// box and the wheel README carry the same sentence, so the three cannot drift (the demo box is checked in
/// tests/demo/check_demo.mjs, the wheel README in tests/python/check_wheel.py).
#[test]
fn readme_states_the_sprint_4_position_in_the_required_words() {
    let root = repo_root();
    let readme = std::fs::read_to_string(root.join("README.md")).unwrap();
    let status = readme
        .split("## Status")
        .nth(1)
        .and_then(|t| t.split("\n## ").next())
        .expect("README has a Status section");
    assert!(
        status.contains("Sprint 4"),
        "the Status section names Sprint 4"
    );
    for needle in [
        "Apple M5 Pro, 48 GB",
        "not measured on 8 GB",
        "Tamil planned for v0.2",
        "Linux and Windows wheels are built only by CI after the owner's push",
        "docs/v0.2-tamil.md",
    ] {
        assert!(readme.contains(needle), "the README lacks {needle:?}");
    }
    assert!(
        !readme.contains("Sprint 4 carry-over"),
        "the README still calls the Linux and Windows wheels a Sprint 4 carry-over"
    );
    let limits = readme
        .split("\n## Limitations")
        .nth(1)
        .and_then(|t| t.split("\n## ").next())
        .expect("README has a Limitations section");
    assert!(
        limits.contains("Linux and Windows wheels are built only by CI after the owner's push"),
        "Limitations does not say where the Linux and Windows wheels come from"
    );
    assert!(
        limits.contains("NOTICE.txt"),
        "Limitations does not mention the demo's NOTICE.txt"
    );
}
