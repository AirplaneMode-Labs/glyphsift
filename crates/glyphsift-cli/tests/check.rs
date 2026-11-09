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
