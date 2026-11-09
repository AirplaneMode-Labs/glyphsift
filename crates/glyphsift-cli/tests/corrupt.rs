//! `glyphsift corrupt` (D3-03), written before the subcommand.

mod common;

use common::{corpus, run, scratch};
use glyphsift_core::corrupt::{Family, Selection, corrupt, parse_p_ppm, sites_json};

#[test]
fn list_families_prints_the_nineteen_families_then_mixed() {
    let r = run(&["corrupt", "--list-families"], b"");
    assert_eq!(r.code, 0, "{}", r.stderr);
    let lines: Vec<String> = r.out().lines().map(str::to_owned).collect();
    let mut want: Vec<String> = Family::ALL.iter().map(|f| f.name().to_owned()).collect();
    want.push("mixed".to_owned());
    assert_eq!(lines, want);
}

#[test]
fn p_zero_is_the_identity_through_the_cli() {
    let text = corpus();
    let r = run(
        &["corrupt", "--family", "mixed", "--p", "0", "--seed", "3"],
        text.as_bytes(),
    );
    assert_eq!(r.code, 0, "{}", r.stderr);
    assert_eq!(r.out(), text);
}

#[test]
fn cli_output_equals_the_library_and_is_repeatable() {
    let text = corpus();
    for family in ["matra_detach", "mixed", "legacy_font", "control_leak"] {
        let args = ["corrupt", "--family", family, "--p", "0.05", "--seed", "7"];
        let a = run(&args, text.as_bytes());
        let b = run(&args, text.as_bytes());
        assert_eq!(a.code, 0, "{}", a.stderr);
        assert_eq!(a.stdout, b.stdout, "{family}: same seed, same bytes");
        let lib = corrupt(
            &text,
            Selection::from_name(family).unwrap(),
            parse_p_ppm("0.05").unwrap(),
            7,
        );
        assert_eq!(a.out(), lib.text, "{family}: CLI equals library");
        assert_ne!(a.out(), text, "{family}: p=0.05 changed something");
    }
}

#[test]
fn the_sites_sidecar_is_written_and_matches_the_library() {
    let text = corpus();
    let dir = scratch("corrupt-sidecar");
    let path = dir.join("out.sites.json");
    let r = run(
        &[
            "corrupt",
            "--family",
            "mixed",
            "--p",
            "0.1",
            "--seed",
            "1",
            "--sites",
            path.to_str().unwrap(),
        ],
        text.as_bytes(),
    );
    assert_eq!(r.code, 0, "{}", r.stderr);
    let sidecar = std::fs::read_to_string(&path).expect("sidecar written");
    let lib = corrupt(&text, Selection::Mixed, 100_000, 1);
    assert_eq!(
        sidecar.trim_end(),
        sites_json(Selection::Mixed, 1, 100_000, &lib)
    );
    let v: serde_json::Value = serde_json::from_str(&sidecar).unwrap();
    assert_eq!(v["family"], "mixed");
    assert_eq!(v["seed"], 1);
    assert_eq!(v["p_ppm"], 100_000);
    assert!(v["sites"].as_array().unwrap().len() > 50);
    let first = &v["sites"][0];
    assert!(first["source"].is_u64() && first["cluster"].is_u64());
    assert!(first["family"].is_string() && first["kinds"].is_array());
}

#[test]
fn bad_arguments_exit_2_and_say_why() {
    let cases: &[&[&str]] = &[
        &["corrupt", "--p", "0.1"],
        &["corrupt", "--family", "matra_drop"],
        &["corrupt", "--family", "no_such_family", "--p", "0.1"],
        &["corrupt", "--family", "matra_drop", "--p", "abc"],
        &["corrupt", "--family", "matra_drop", "--p", "1.5"],
        &["corrupt", "--family", "matra_drop", "--p", "-0.1"],
        &["corrupt", "--family", "matra_drop", "--p", "0.0000001"],
        &[
            "corrupt",
            "--family",
            "matra_drop",
            "--p",
            "0.1",
            "--seed",
            "x",
        ],
        &[
            "corrupt",
            "--family",
            "matra_drop",
            "--p",
            "0.1",
            "--seed",
            "-1",
        ],
        &[
            "corrupt",
            "--family",
            "matra_drop",
            "--p",
            "0.1",
            "--seed",
            "18446744073709551616",
        ],
        &["corrupt", "--family", "matra_drop", "--p", "0.1", "--bogus"],
    ];
    for args in cases {
        let r = run(args, b"\xe0\xa4\x95");
        assert_eq!(
            r.code, 2,
            "{args:?} should be a usage error, stderr: {}",
            r.stderr
        );
        assert!(r.stdout.is_empty(), "{args:?} must not print output");
        assert!(!r.stderr.is_empty(), "{args:?} must explain itself");
    }
}

#[test]
fn a_u64_seed_up_to_the_maximum_is_accepted() {
    let r = run(
        &[
            "corrupt",
            "--family",
            "matra_drop",
            "--p",
            "1",
            "--seed",
            "18446744073709551615",
        ],
        "का".as_bytes(),
    );
    assert_eq!(r.code, 0, "{}", r.stderr);
    assert_eq!(r.out(), "क");
}

#[test]
fn invalid_utf8_input_exits_1() {
    let r = run(
        &["corrupt", "--family", "matra_drop", "--p", "0.5"],
        b"\xff\xfe\xfd",
    );
    assert_eq!(r.code, 1);
    assert!(r.stderr.contains("UTF-8"), "{}", r.stderr);
}

#[test]
fn an_unwritable_sidecar_path_exits_1() {
    let r = run(
        &[
            "corrupt",
            "--family",
            "matra_drop",
            "--p",
            "0.5",
            "--sites",
            "/no/such/dir/x.json",
        ],
        "का".as_bytes(),
    );
    assert_eq!(r.code, 1);
    assert!(r.stderr.contains("/no/such/dir/x.json"), "{}", r.stderr);
}
