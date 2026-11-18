//! The gate call (Sprint 5, D3-01, TD-42), written before `gate.rs` existed.
//!
//! `gate(text, threshold_ppm)` answers one question for a pipeline that ingests extracted text chunk
//! by chunk: score this chunk, hold it back, or say that it is not Devanagari so no score applies.
//! These tests pin the rules in `docs/gate.md`:
//!
//! - letters are `char::is_alphabetic()` or in U+0900..U+097F, U+A8E0..U+A8FF, U+1CD0..U+1CFF;
//! - `devanagari_ppm` is the integer floor of the block letters over all letters, in parts per million;
//! - no letters: script `none`; under 500,000 ppm: script `other`; both `not_scored` with `ppm` null;
//! - otherwise `ppm` is exactly `validate(text).score.ppm` and the verdict is `pass` when `ppm` is at
//!   or above the threshold, else `hold`;
//! - input over 4 MiB is refused, a threshold outside 0..=1,000,000 is refused;
//! - the default threshold sits in the gap the committed benchmark CSV shows (derivation in docs/gate.md).

use glyphsift_core::{
    DEFAULT_GATE_THRESHOLD_PPM, Error, GATE_SPEC, GateReport, GateScript, GateVerdict,
    MAX_INPUT_BYTES, gate, gate_to_canonical_json, parse_threshold, validate,
};

const CLEAN: &str = "नमस्ते।";
// Four clusters, one broken (unexpected_code_point, weight 1000): score 750_000.
const DAMAGED: &str = "कखग\u{FFFD}";

fn text_of(parts: &[(&str, usize)]) -> String {
    parts.iter().map(|(s, n)| s.repeat(*n)).collect()
}

#[test]
fn the_spec_string_and_the_default_threshold_are_pinned() {
    assert_eq!(GATE_SPEC, "glyphsift.gate/0.1");
    // Derived from docs/score-vs-noise.csv in docs/gate.md; changing it is a CHANGELOG entry.
    assert_eq!(DEFAULT_GATE_THRESHOLD_PPM, 975_000);
}

#[test]
fn clean_devanagari_passes_with_the_default_threshold() {
    let r = gate(CLEAN, None).unwrap();
    assert_eq!(r.spec, GATE_SPEC);
    assert!(r.scored);
    assert_eq!(r.script, GateScript::Devanagari);
    assert_eq!(r.devanagari_ppm, 1_000_000);
    assert_eq!(r.ppm, Some(1_000_000));
    assert_eq!(r.threshold_ppm, DEFAULT_GATE_THRESHOLD_PPM);
    assert_eq!(r.verdict, GateVerdict::Pass);
}

#[test]
fn damaged_devanagari_is_held_and_the_threshold_comparison_is_inclusive() {
    let r = gate(DAMAGED, None).unwrap();
    assert!(r.scored);
    assert_eq!(r.ppm, Some(750_000));
    assert_eq!(r.verdict, GateVerdict::Hold);
    // threshold equal to the score passes; one above holds; 0 always passes a scored chunk.
    assert_eq!(
        gate(DAMAGED, Some(750_000)).unwrap().verdict,
        GateVerdict::Pass
    );
    assert_eq!(
        gate(DAMAGED, Some(750_001)).unwrap().verdict,
        GateVerdict::Hold
    );
    assert_eq!(gate(DAMAGED, Some(0)).unwrap().verdict, GateVerdict::Pass);
    assert_eq!(
        gate(DAMAGED, Some(1_000_000)).unwrap().verdict,
        GateVerdict::Hold
    );
    assert_eq!(
        gate(CLEAN, Some(1_000_000)).unwrap().verdict,
        GateVerdict::Pass,
        "a clean chunk scores exactly 1000000"
    );
    // The report names the threshold that was applied.
    assert_eq!(gate(DAMAGED, Some(750_001)).unwrap().threshold_ppm, 750_001);
}

#[test]
fn a_threshold_outside_the_ppm_range_is_refused() {
    for bad in [1_000_001u32, u32::MAX] {
        let err = gate(CLEAN, Some(bad)).unwrap_err();
        assert_eq!(
            err,
            Error::InvalidThreshold {
                value: i64::from(bad)
            }
        );
        assert!(err.to_string().contains("threshold"), "{err}");
    }
    assert_eq!(parse_threshold(0), Ok(0));
    assert_eq!(parse_threshold(1_000_000), Ok(1_000_000));
    assert_eq!(
        parse_threshold(-1),
        Err(Error::InvalidThreshold { value: -1 })
    );
    assert_eq!(
        parse_threshold(1_000_001),
        Err(Error::InvalidThreshold { value: 1_000_001 })
    );
    assert_eq!(
        parse_threshold(i64::MAX),
        Err(Error::InvalidThreshold { value: i64::MAX })
    );
}

#[test]
fn text_with_no_letters_is_script_none_and_not_scored() {
    for text in [
        "", " ", "\n\n", "123", "?!.,;", "\u{200D}", "\u{FFFD}", "😀",
    ] {
        let r = gate(text, None).unwrap();
        assert_eq!(r.script, GateScript::None, "{text:?}");
        assert!(!r.scored, "{text:?}");
        assert_eq!(r.devanagari_ppm, 0, "{text:?}");
        assert_eq!(r.ppm, None, "{text:?}");
        assert_eq!(r.verdict, GateVerdict::NotScored, "{text:?}");
        assert_eq!(r.threshold_ppm, DEFAULT_GATE_THRESHOLD_PPM);
    }
}

#[test]
fn other_scripts_pass_through_marked_not_scored() {
    for text in [
        "hello world",
        "Привет",
        "தமிழ்",
        "বাংলা",
        "日本語",
        "naïve café",
    ] {
        let r = gate(text, None).unwrap();
        assert_eq!(r.script, GateScript::Other, "{text:?}");
        assert!(!r.scored, "{text:?}");
        assert_eq!(r.ppm, None, "{text:?}");
        assert_eq!(r.verdict, GateVerdict::NotScored, "{text:?}");
    }
    // A scored threshold of any value never turns a not-scored chunk into pass or hold.
    assert_eq!(
        gate("hello", Some(1_000_000)).unwrap().verdict,
        GateVerdict::NotScored
    );
    assert_eq!(
        gate("hello", Some(0)).unwrap().verdict,
        GateVerdict::NotScored
    );
}

#[test]
fn the_devanagari_share_boundary_is_500_000_ppm_exactly() {
    // One Devanagari letter and one Latin letter: exactly 500,000.
    let r = gate("क a", None).unwrap();
    assert_eq!(r.devanagari_ppm, 500_000);
    assert_eq!(r.script, GateScript::Devanagari);
    assert!(r.scored);
    // One and two: 333,333 (floor).
    let r = gate("क aa", None).unwrap();
    assert_eq!(r.devanagari_ppm, 333_333);
    assert_eq!(r.script, GateScript::Other);
    assert!(!r.scored);
    // 250,000 Devanagari letters against 250,001 Latin letters: 499,999.99.. floors to 499,999.
    let below = text_of(&[("क", 250_000), ("a", 250_001)]);
    let r = gate(&below, None).unwrap();
    assert_eq!(r.devanagari_ppm, 499_999);
    assert_eq!(r.script, GateScript::Other);
    assert_eq!(r.verdict, GateVerdict::NotScored);
    assert_eq!(r.ppm, None);
    // 250,000 against 250,000: exactly 500,000, scored.
    let at = text_of(&[("क", 250_000), ("a", 250_000)]);
    let r = gate(&at, None).unwrap();
    assert_eq!(r.devanagari_ppm, 500_000);
    assert_eq!(r.script, GateScript::Devanagari);
    assert!(r.scored);
    assert!(r.ppm.is_some());
}

#[test]
fn letters_are_alphabetic_chars_plus_three_blocks() {
    // Devanagari digits, danda, matras, virama are in U+0900..U+097F: they count as letters and as
    // Devanagari. ASCII digits and punctuation count as neither.
    let r = gate("१२३ 456 !?", None).unwrap();
    assert_eq!(
        r.devanagari_ppm, 1_000_000,
        "3 Devanagari digits, no other letter"
    );
    assert_eq!(r.script, GateScript::Devanagari);
    // Devanagari Extended (U+A8E0..U+A8FF) and Vedic Extensions (U+1CD0..U+1CFF) are counted.
    for cp in [
        '\u{A8E0}', '\u{A8FF}', '\u{1CD0}', '\u{1CFF}', '\u{0900}', '\u{097F}',
    ] {
        let t = format!("{cp}{cp}");
        let r = gate(&t, None).unwrap();
        assert_eq!(r.devanagari_ppm, 1_000_000, "{cp:?}");
    }
    // Just outside the blocks: U+0980 (Bengali) is alphabetic and not Devanagari; U+A8DF and U+A900
    // are outside the extended block.
    let r = gate("\u{0980}", None).unwrap();
    assert_eq!(r.devanagari_ppm, 0);
    assert_eq!(r.script, GateScript::Other);
    assert_eq!(gate("\u{A900}", None).unwrap().devanagari_ppm, 0);
    // A combining mark outside the blocks that is Alphabetic counts as a letter, not as Devanagari.
    let r = gate("क\u{0345}", None).unwrap();
    assert_eq!(r.devanagari_ppm, 500_000);
    // Mixed text, floor division: 2 of 3 letters is 666,666.
    let r = gate("कख a", None).unwrap();
    assert_eq!(r.devanagari_ppm, 666_666);
    assert_eq!(r.script, GateScript::Devanagari);
}

#[test]
fn a_scored_chunk_has_exactly_the_score_validate_gives() {
    let corpus = std::fs::read_to_string(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../bench/corpus/clean.txt"),
    )
    .expect("bench/corpus/clean.txt");
    let mut texts: Vec<String> = corpus.lines().map(str::to_owned).collect();
    texts.push(corpus.clone());
    for text in ["कखग\u{FFFD}", "ोम काा ं नमस्ते िदुनिया", "क\r\nख\n", "क्‍ष"]
    {
        texts.push(text.to_owned());
    }
    let mut checked = 0;
    for text in &texts {
        let r = gate(text, None).unwrap();
        if r.scored {
            assert_eq!(r.ppm, Some(validate(text).unwrap().score.ppm), "{text:?}");
            checked += 1;
        }
    }
    assert!(checked > 280, "the corpus lines are scored: {checked}");
}

#[test]
fn canonical_json_is_compact_in_field_order() {
    let pass = gate(CLEAN, None).unwrap();
    assert_eq!(
        gate_to_canonical_json(&pass),
        "{\"spec\":\"glyphsift.gate/0.1\",\"scored\":true,\"script\":\"devanagari\",\
         \"devanagari_ppm\":1000000,\"ppm\":1000000,\"threshold_ppm\":975000,\"verdict\":\"pass\"}"
    );
    let hold = gate(DAMAGED, Some(800_000)).unwrap();
    assert_eq!(
        gate_to_canonical_json(&hold),
        "{\"spec\":\"glyphsift.gate/0.1\",\"scored\":true,\"script\":\"devanagari\",\
         \"devanagari_ppm\":1000000,\"ppm\":750000,\"threshold_ppm\":800000,\"verdict\":\"hold\"}"
    );
    let other = gate("hello", None).unwrap();
    assert_eq!(
        gate_to_canonical_json(&other),
        "{\"spec\":\"glyphsift.gate/0.1\",\"scored\":false,\"script\":\"other\",\
         \"devanagari_ppm\":0,\"ppm\":null,\"threshold_ppm\":975000,\"verdict\":\"not_scored\"}"
    );
    let none = gate("", Some(1)).unwrap();
    assert_eq!(
        gate_to_canonical_json(&none),
        "{\"spec\":\"glyphsift.gate/0.1\",\"scored\":false,\"script\":\"none\",\
         \"devanagari_ppm\":0,\"ppm\":null,\"threshold_ppm\":1,\"verdict\":\"not_scored\"}"
    );
    for r in [pass, hold, other, none] {
        let back: GateReport = serde_json::from_str(&gate_to_canonical_json(&r)).unwrap();
        assert_eq!(back, r);
    }
}

#[test]
fn input_over_4_mib_is_refused_and_exactly_4_mib_is_accepted() {
    let at = "a".repeat(MAX_INPUT_BYTES);
    assert!(gate(&at, None).is_ok());
    let over = "a".repeat(MAX_INPUT_BYTES + 1);
    let err = gate(&over, None).unwrap_err();
    assert_eq!(
        err,
        Error::InputTooLarge {
            bytes: MAX_INPUT_BYTES + 1,
            max: MAX_INPUT_BYTES
        }
    );
    assert!(err.to_string().contains("too large"));
    // Multi-byte characters across the boundary: 3-byte letters padded with ASCII to the exact limit.
    let n = (MAX_INPUT_BYTES - 1) / 3;
    let pad = MAX_INPUT_BYTES - 3 * n;
    let exact = format!("{}{}", "क".repeat(n), "a".repeat(pad));
    assert_eq!(exact.len(), MAX_INPUT_BYTES);
    assert!(gate(&exact, None).is_ok());
    assert!(gate(&format!("{exact}a"), None).is_err());
    // The size check comes before the threshold check does not matter, but both refuse.
    assert!(gate(&over, Some(2_000_000)).is_err());
}

/// xorshift64* (Vigna 2014), the generator the whole lane uses.
struct XorShift64Star(u64);

impl XorShift64Star {
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
}

/// Alphabet for the no-panic test: the Devanagari block edges and interior, combining marks of other
/// scripts, joiners, tags, controls, Latin, digits, emoji, noncharacters and the private use area.
const ALPHABET: &[u32] = &[
    0x0900, 0x0901, 0x0902, 0x0903, 0x0904, 0x0915, 0x0939, 0x093C, 0x093E, 0x094D, 0x094E, 0x0950,
    0x0958, 0x095F, 0x0964, 0x0966, 0x096F, 0x0970, 0x0971, 0x0978, 0x097F, 0x0980, 0x0BCD, 0x0301,
    0x0345, 0x20D7, 0x1CD0, 0x1CFF, 0xA8E0, 0xA8FF, 0xA8DF, 0xA900, 0x200C, 0x200D, 0x200E, 0xFEFF,
    0xFE0F, 0xE0001, 0xE0041, 0xE007F, 0x0041, 0x007A, 0x0030, 0x0020, 0x000A, 0x000D, 0x0009,
    0x0000, 0x001F, 0x007F, 0x0085, 0xFFFD, 0xFFFE, 0xFFFF, 0xF0D0, 0xE000, 0x1F468, 0x1F3F4,
    0x10FFFF, 0x10000, 0x00E9, 0x0BA4, 0x09AC,
];

#[test]
fn ten_thousand_seeded_random_strings_never_panic_and_stay_consistent() {
    let mut rng = XorShift64Star(0x5eed_5eed_5eed_5eed);
    let (mut scored, mut held) = (0u32, 0u32);
    let thresholds = [None, Some(0), Some(1), Some(975_000), Some(1_000_000)];
    for n in 0..10_000u32 {
        let len = rng.next() % 40;
        let text: String = (0..len)
            .map(|_| {
                let r = rng.next();
                // One in eight draws is any scalar value at all (not in the table).
                if r.is_multiple_of(8) {
                    let raw = ((r >> 8) % 0x11_0000) as u32;
                    char::from_u32(raw).unwrap_or('\u{FFFD}')
                } else {
                    char::from_u32(ALPHABET[((r >> 8) as usize) % ALPHABET.len()]).unwrap()
                }
            })
            .collect();
        let threshold = thresholds[(n as usize) % thresholds.len()];
        let r = gate(&text, threshold).unwrap_or_else(|e| panic!("input {n} {text:?}: {e}"));
        assert!(r.devanagari_ppm <= 1_000_000, "{n} {text:?}");
        assert_eq!(r.spec, GATE_SPEC);
        match r.script {
            GateScript::None => {
                assert_eq!(r.devanagari_ppm, 0, "{n} {text:?}");
                assert_eq!(r.verdict, GateVerdict::NotScored);
                assert_eq!(r.ppm, None);
                assert!(!r.scored);
            }
            GateScript::Other => {
                assert!(r.devanagari_ppm < 500_000, "{n} {text:?}");
                assert_eq!(r.verdict, GateVerdict::NotScored);
                assert_eq!(r.ppm, None);
                assert!(!r.scored);
            }
            GateScript::Devanagari => {
                scored += 1;
                held += u32::from(r.verdict == GateVerdict::Hold);
                assert!(r.devanagari_ppm >= 500_000, "{n} {text:?}");
                assert!(r.scored);
                let ppm = r.ppm.expect("scored chunks carry a score");
                assert_eq!(ppm, validate(&text).unwrap().score.ppm, "{n} {text:?}");
                let want = if ppm >= r.threshold_ppm {
                    GateVerdict::Pass
                } else {
                    GateVerdict::Hold
                };
                assert_eq!(r.verdict, want, "{n} {text:?}");
            }
        }
        // Serialising never fails and always round-trips.
        let json = gate_to_canonical_json(&r);
        assert_eq!(serde_json::from_str::<GateReport>(&json).unwrap(), r);
    }
    // The loop reaches every branch.
    assert!(scored > 300 && held > 100, "{scored} scored, {held} held");
    // The 4 MiB boundary with random content: exactly the limit is accepted, one byte over is refused.
    for k in 0..3u64 {
        let mut text = String::with_capacity(MAX_INPUT_BYTES + 4);
        while text.len() < MAX_INPUT_BYTES {
            let r = rng.next() ^ k;
            let c = char::from_u32(ALPHABET[((r >> 8) as usize) % ALPHABET.len()]).unwrap();
            if text.len() + c.len_utf8() > MAX_INPUT_BYTES {
                break;
            }
            text.push(c);
        }
        while text.len() < MAX_INPUT_BYTES {
            text.push('a');
        }
        assert_eq!(text.len(), MAX_INPUT_BYTES);
        let r = gate(&text, None).unwrap();
        assert_eq!(r.scored, r.ppm.is_some());
        text.push('a');
        assert!(matches!(
            gate(&text, None),
            Err(Error::InputTooLarge { .. })
        ));
    }
}

/// The default threshold is not a guess: it sits in the gap that docs/score-vs-noise.csv shows between
/// the `mixed` family at p=0.1 (every seed above it) and at p=0.2 (every seed below it). docs/gate.md
/// quotes these figures; the last test below checks that it does.
fn mixed_scores_by_p() -> std::collections::BTreeMap<String, Vec<u32>> {
    let csv = std::fs::read_to_string(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docs/score-vs-noise.csv"),
    )
    .expect("docs/score-vs-noise.csv");
    let mut by_p: std::collections::BTreeMap<String, Vec<u32>> = Default::default();
    for line in csv.lines().skip(1) {
        let cols: Vec<&str> = line.split(',').collect();
        if cols[0] == "mixed" {
            by_p.entry(cols[1].to_owned())
                .or_default()
                .push(cols[5].parse().unwrap());
        }
    }
    by_p
}

#[test]
fn the_default_threshold_sits_in_the_gap_between_mixed_noise_01_and_02() {
    let by_p = mixed_scores_by_p();
    for p in ["0", "0.01", "0.02", "0.05", "0.1"] {
        let lowest = *by_p[p].iter().min().unwrap();
        assert!(
            lowest >= DEFAULT_GATE_THRESHOLD_PPM,
            "mixed p={p}: lowest seed {lowest} would be held"
        );
    }
    for p in ["0.2", "0.4"] {
        let highest = *by_p[p].iter().max().unwrap();
        assert!(
            highest < DEFAULT_GATE_THRESHOLD_PPM,
            "mixed p={p}: highest seed {highest} would pass"
        );
    }
}

#[test]
fn docs_gate_md_quotes_the_figures_it_derives_the_default_from() {
    let doc = std::fs::read_to_string(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docs/gate.md"),
    )
    .expect("docs/gate.md");
    let by_p = mixed_scores_by_p();
    let min_01 = by_p["0.1"].iter().min().unwrap();
    let max_02 = by_p["0.2"].iter().max().unwrap();
    for needle in [
        DEFAULT_GATE_THRESHOLD_PPM.to_string(),
        min_01.to_string(),
        max_02.to_string(),
        GATE_SPEC.to_owned(),
        "not_scored".to_owned(),
        "hold".to_owned(),
        "docs/score-vs-noise.csv".to_owned(),
    ] {
        assert!(
            doc.contains(&needle),
            "docs/gate.md does not mention {needle:?}"
        );
    }
    for heading in [
        "## What a hold means",
        "## Which noise to use to produce a hold",
    ] {
        assert!(
            doc.contains(heading),
            "docs/gate.md has no section {heading:?}"
        );
    }
}
