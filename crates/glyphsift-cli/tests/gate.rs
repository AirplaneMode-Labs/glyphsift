//! `glyphsift gate [--threshold-ppm N] FILE|-` (Sprint 5, D3-01, TD-42), written before the command.
//!
//! The command prints the canonical `glyphsift.gate/0.1` JSON for the text and exits 0 whatever the
//! verdict is (`pass`, `hold` and `not_scored` are all answers, not failures). Exit codes: 1 I/O error or
//! input over 4 MiB; 2 usage error, which here includes input that is not valid UTF-8 and a threshold
//! outside 0..=1000000. There is no exit code 3 or 4 for `gate`.

mod common;

use common::{run, scratch};
use glyphsift_core::{DEFAULT_GATE_THRESHOLD_PPM, gate, gate_to_canonical_json};

const CLEAN: &str = "नमस्ते।";
// Four clusters, one broken: 750_000.
const DAMAGED: &str = "कखग\u{FFFD}";

fn expected(text: &str, threshold: Option<u32>) -> String {
    format!(
        "{}\n",
        gate_to_canonical_json(&gate(text, threshold).unwrap())
    )
}

#[test]
fn gate_prints_the_canonical_json_from_stdin_for_every_verdict() {
    for text in [CLEAN, DAMAGED, "", "hello", "क a", "क\r\nख\n", "१२३"] {
        let r = run(&["gate", "-"], text.as_bytes());
        assert_eq!(r.code, 0, "{text:?}: {}", r.stderr);
        assert_eq!(r.out(), expected(text, None), "{text:?}");
    }
    let v: serde_json::Value =
        serde_json::from_str(&run(&["gate", "-"], DAMAGED.as_bytes()).out()).unwrap();
    assert_eq!(v["spec"], "glyphsift.gate/0.1");
    assert_eq!(v["verdict"], "hold");
    assert_eq!(v["ppm"], 750_000);
    assert_eq!(v["threshold_ppm"], DEFAULT_GATE_THRESHOLD_PPM);
}

#[test]
fn gate_reads_a_file() {
    let dir = scratch("gate-file");
    let path = dir.join("chunk.txt");
    std::fs::write(&path, CLEAN).unwrap();
    let r = run(&["gate", path.to_str().unwrap()], b"");
    assert_eq!(r.code, 0, "{}", r.stderr);
    assert_eq!(r.out(), expected(CLEAN, None));
}

#[test]
fn threshold_ppm_is_applied_and_reported() {
    for threshold in [0u32, 1, 750_000, 750_001, 975_000, 1_000_000] {
        let t = threshold.to_string();
        let r = run(&["gate", "--threshold-ppm", &t, "-"], DAMAGED.as_bytes());
        assert_eq!(r.code, 0, "--threshold-ppm {t}: {}", r.stderr);
        assert_eq!(r.out(), expected(DAMAGED, Some(threshold)), "{t}");
    }
    // The flag may come after the file argument too.
    let r = run(
        &["gate", "-", "--threshold-ppm", "750000"],
        DAMAGED.as_bytes(),
    );
    assert_eq!(r.code, 0, "{}", r.stderr);
    assert!(r.out().contains("\"verdict\":\"pass\""), "{}", r.out());
}

#[test]
fn exit_code_is_0_for_hold_and_not_scored_too() {
    assert_eq!(run(&["gate", "-"], DAMAGED.as_bytes()).code, 0);
    assert_eq!(run(&["gate", "-"], b"hello world").code, 0);
    assert_eq!(run(&["gate", "-"], b"").code, 0);
}

#[test]
fn invalid_utf8_is_a_usage_error_exit_2() {
    for bytes in [
        &b"\xff\xfe\xfd"[..],
        // A lone surrogate in WTF-8 (U+D800): the only way a native program meets one.
        &b"\xe0\xa4\xa8\xed\xa0\x80\xe0\xa4\xae"[..],
        // A truncated three-byte sequence.
        &b"\xe0\xa4"[..],
    ] {
        let r = run(&["gate", "-"], bytes);
        assert_eq!(r.code, 2, "{bytes:?}: {}", r.stderr);
        assert!(r.stdout.is_empty(), "{bytes:?} printed to stdout");
        assert!(r.stderr.contains("UTF-8"), "{}", r.stderr);
    }
}

#[test]
fn io_errors_and_oversize_input_exit_1() {
    let r = run(&["gate", "/no/such/file.txt"], b"");
    assert_eq!(r.code, 1);
    assert!(r.stdout.is_empty());
    assert!(r.stderr.contains("/no/such/file.txt"), "{}", r.stderr);
    let dir = scratch("gate-dir");
    assert_eq!(run(&["gate", dir.to_str().unwrap()], b"").code, 1);
    let big = "क".repeat(glyphsift_core::MAX_INPUT_BYTES / 3 + 1);
    let r = run(&["gate", "-"], big.as_bytes());
    assert_eq!(r.code, 1);
    assert!(r.stderr.contains("too large"), "{}", r.stderr);
}

#[test]
fn usage_errors_exit_2() {
    let cases: &[&[&str]] = &[
        &["gate"],
        &["gate", "-", "--threshold-ppm"],
        &["gate", "-", "--threshold-ppm", "abc"],
        &["gate", "-", "--threshold-ppm", "-5"],
        &["gate", "-", "--threshold-ppm", "1000001"],
        &["gate", "-", "--threshold-ppm", "1.5"],
        &["gate", "-", "--threshold-ppm", ""],
        &["gate", "-", "--bogus"],
        &["gate", "-", "extra"],
    ];
    for args in cases {
        let r = run(args, b"");
        assert_eq!(r.code, 2, "{args:?}: {}", r.stderr);
        assert!(r.stdout.is_empty(), "{args:?} printed to stdout");
    }
}

#[test]
fn help_lists_gate_and_documents_its_exit_codes() {
    let top = run(&["--help"], b"");
    assert_eq!(top.code, 0, "{}", top.stderr);
    assert!(top.out().contains("gate"), "{}", top.out());
    let r = run(&["gate", "--help"], b"");
    assert_eq!(r.code, 0, "{}", r.stderr);
    let help = r.out();
    for needle in ["--threshold-ppm", "975000", "not_scored", "UTF-8"] {
        assert!(
            help.contains(needle),
            "gate --help lacks {needle:?}:\n{help}"
        );
    }
}
