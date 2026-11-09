//! No-panic fuzz test for `validate()`.
//!
//! 20,000 strings drawn with xorshift64* (seed 1) over U+0000..U+097F plus ZWJ, ZWNJ and a slice of
//! the private use area (where legacy-font conversions land). For every input: no panic, the
//! issues are in input order, every issue names a code point that is in its cluster, and every
//! issue's cluster index is below the cluster count.
//!
//! The canonical JSON of all 20,000 reports is folded into one FNV-1a 64-bit hash; the same hash
//! is asserted by `tests/wasm/run_wasm_safety.mjs` over the WASM build, so the two runtimes agree
//! on 20,000 inputs, not just on the handful of golden samples.

use glyphsift_core::{to_canonical_json, validate};

/// xorshift64* (Vigna 2014): the generator `docs/corruption-generator.md` names for the whole lane.
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

/// Alphabet: 0x980 code points U+0000..U+097F, then ZWJ, ZWNJ, then U+F0D0..U+F0DF (16 PUA).
const ALPHABET: u64 = 0x980 + 2 + 16;

fn alphabet_char(i: u64) -> char {
    let cp = match i {
        0..0x980 => i as u32,
        0x980 => 0x200D,
        0x981 => 0x200C,
        _ => 0xF0D0 + (i - 0x982) as u32,
    };
    char::from_u32(cp).expect("alphabet holds scalar values only")
}

/// The fuzz set. Lengths 0..=24 code points.
fn fuzz_strings() -> Vec<String> {
    let mut rng = XorShift64Star(1);
    (0..20_000)
        .map(|_| {
            let len = rng.next() % 25;
            (0..len)
                .map(|_| alphabet_char(rng.next() % ALPHABET))
                .collect()
        })
        .collect()
}

const FNV_OFFSET: u64 = 0xcbf2_9ce4_8422_2325;
const FNV_PRIME: u64 = 0x0000_0100_0000_01b3;

fn fnv1a(mut h: u64, bytes: &[u8]) -> u64 {
    for &b in bytes {
        h ^= u64::from(b);
        h = h.wrapping_mul(FNV_PRIME);
    }
    h
}

/// FNV-1a 64 over each report's canonical JSON followed by a newline.
/// `tests/wasm/run_wasm_safety.mjs` carries the same constant.
// Report 0.2 (lines, score and by_kind included). Changing a rule, a weight or the report shape
// changes this value: re-pin it here and in tests/wasm/run_wasm_safety.mjs, and say why in CHANGELOG.
const FUZZ_HASH: u64 = 0x3406f55bff039ed3;

#[test]
fn twenty_thousand_random_strings_never_panic_and_stay_ordered() {
    let mut hash = FNV_OFFSET;
    for (n, text) in fuzz_strings().iter().enumerate() {
        let report = validate(text).unwrap_or_else(|e| panic!("input {n} {text:?}: {e}"));
        assert_eq!(report.summary.cluster_count, report.clusters.len());
        let mut prev_cluster = 0usize;
        let mut prev_pos = 0usize;
        for issue in &report.issues {
            assert!(
                issue.cluster < report.summary.cluster_count,
                "input {n} {text:?}: issue cluster {} out of range",
                issue.cluster
            );
            assert!(
                issue.cluster >= prev_cluster,
                "input {n}: issues out of order"
            );
            if issue.cluster != prev_cluster {
                prev_pos = 0;
            }
            prev_cluster = issue.cluster;
            let cp = issue
                .code_point
                .as_deref()
                .unwrap_or_else(|| panic!("input {n}: issue without a code point"));
            let cps = &report.clusters[issue.cluster].code_points;
            let pos = cps[prev_pos..]
                .iter()
                .position(|c| c == cp)
                .unwrap_or_else(|| panic!("input {n} {text:?}: {cp} not at or after position {prev_pos} in its cluster"));
            prev_pos += pos;
        }
        hash = fnv1a(hash, to_canonical_json(&report).as_bytes());
        hash = fnv1a(hash, b"\n");
    }
    println!("fuzz hash: 0x{hash:016x}");
    assert_eq!(
        hash, FUZZ_HASH,
        "fuzz set output changed; update FUZZ_HASH here and in tests/wasm/run_wasm_safety.mjs"
    );
}

#[test]
fn fuzz_set_is_the_same_every_run() {
    // Guards the generator itself: the first and last strings are pinned by length and content.
    let a = fuzz_strings();
    let b = fuzz_strings();
    assert_eq!(a, b);
    assert_eq!(a.len(), 20_000);
    assert!(a.iter().all(|s| s.chars().count() <= 24));
    assert!(
        a.iter()
            .any(|s| s.chars().any(|c| ('\u{F0D0}'..='\u{F0DF}').contains(&c)))
    );
}
