//! Seeded, deterministic OCR-corruption generator (`docs/corruption-generator.md`).
//!
//! The generator takes clean text, splits it into the same UAX #29 clusters the validator uses and
//! treats every cluster as a candidate *site*. For a single family, site `i` is the `i`-th cluster
//! of the clean input; under `mixed`, site `i` belongs to family
//! `ALL[splitmix64(seed ^ i) mod 19]`. A family decides from the cluster's own text (and, for two
//! families, its neighbour) whether the site is *eligible*.
//!
//! Coupling across `p`, which makes the benchmark's curves comparable step to step:
//!
//! - the draw for site `i` is `u_i = xorshift64*(splitmix64(seed ^ fnv1a64(family) ^ i))`, with
//!   `fnv1a64("mixed")` standing in for the family name under `mixed`;
//! - site `i` is corrupted iff `((u_i >> 11) * 1_000_000) >> 53 < p_ppm`, in 128-bit integer
//!   arithmetic, so the set of corrupted sites at one `p` is a subset of the set at any larger `p`;
//! - what the corruption does comes from a second stream,
//!   `xorshift64*(splitmix64(splitmix64(seed ^ fnv1a64(family) ^ i) ^ 1))`, which does not depend on
//!   `p`: a site that is corrupted at two values of `p` is corrupted identically at both.
//!
//! No floating point, no clock, no environment, no operating-system randomness.

use serde::Serialize;
use unicode_segmentation::UnicodeSegmentation;

use crate::report::IssueKind;
use crate::tables::{Class, classify};

/// The p schedule used by the benchmark, as the decimal strings the CLI accepts.
pub const SCHEDULE: [&str; 7] = ["0", "0.01", "0.02", "0.05", "0.1", "0.2", "0.4"];
/// The same schedule in parts per million.
pub const SCHEDULE_PPM: [u32; 7] = [0, 10_000, 20_000, 50_000, 100_000, 200_000, 400_000];

/// Whether a family is expected to be visible to structural validation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Strength {
    /// The family's "rules it should trigger" column is non-empty: the score must fall with p.
    Triggering,
    /// "None directly": structural validation cannot see it; the curve is reported, not gated.
    NoneDirectly,
}

/// One named noise family.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Family {
    MatraDrop,
    MatraSwap,
    MatraDouble,
    MatraDetach,
    NuktaLoss,
    NuktaSpurious,
    ViramaDelete,
    ViramaInsert,
    BinduSwap,
    SignOrder,
    RephMisplace,
    JoinerInject,
    LegacyFont,
    OcrConfusion,
    WordBoundary,
    DigitDanda,
    RandomSubstitution,
    MixedScript,
    ControlLeak,
}

impl Family {
    /// Every family, in the order of the table in `docs/corruption-generator.md`.
    pub const ALL: [Family; 19] = [
        Family::MatraDrop,
        Family::MatraSwap,
        Family::MatraDouble,
        Family::MatraDetach,
        Family::NuktaLoss,
        Family::NuktaSpurious,
        Family::ViramaDelete,
        Family::ViramaInsert,
        Family::BinduSwap,
        Family::SignOrder,
        Family::RephMisplace,
        Family::JoinerInject,
        Family::LegacyFont,
        Family::OcrConfusion,
        Family::WordBoundary,
        Family::DigitDanda,
        Family::RandomSubstitution,
        Family::MixedScript,
        Family::ControlLeak,
    ];

    /// The snake_case name used on the command line, in the CSV and in the docs table.
    pub fn name(self) -> &'static str {
        match self {
            Family::MatraDrop => "matra_drop",
            Family::MatraSwap => "matra_swap",
            Family::MatraDouble => "matra_double",
            Family::MatraDetach => "matra_detach",
            Family::NuktaLoss => "nukta_loss",
            Family::NuktaSpurious => "nukta_spurious",
            Family::ViramaDelete => "virama_delete",
            Family::ViramaInsert => "virama_insert",
            Family::BinduSwap => "bindu_swap",
            Family::SignOrder => "sign_order",
            Family::RephMisplace => "reph_misplace",
            Family::JoinerInject => "joiner_inject",
            Family::LegacyFont => "legacy_font",
            Family::OcrConfusion => "ocr_confusion",
            Family::WordBoundary => "word_boundary",
            Family::DigitDanda => "digit_danda",
            Family::RandomSubstitution => "random_substitution",
            Family::MixedScript => "mixed_script",
            Family::ControlLeak => "control_leak",
        }
    }

    /// Parse a family name.
    pub fn from_name(name: &str) -> Option<Family> {
        Family::ALL.into_iter().find(|f| f.name() == name)
    }

    /// The rules this family's sites can be expected to trigger (the docs table column).
    pub fn triggers(self) -> &'static [IssueKind] {
        use IssueKind::*;
        match self {
            Family::MatraDouble => &[DoubleMatra],
            Family::MatraDetach => &[DependentVowelWithoutBase],
            Family::NuktaSpurious => &[NuktaAfterMatra, NuktaOnNonConsonant],
            Family::ViramaInsert => &[ViramaAfterMatra, ViramaWithoutConsonant],
            Family::BinduSwap => &[MultipleAnusvaraLike],
            Family::SignOrder => &[SignBeforeMatra, VisargaBeforeAnusvara],
            Family::JoinerInject => &[ZwjZwnjMisplaced],
            Family::LegacyFont => &[DependentVowelWithoutBase, UnexpectedCodePoint],
            Family::WordBoundary => &[DependentVowelWithoutBase, ViramaWithoutConsonant],
            Family::MixedScript => &[MixedScriptInCluster],
            Family::ControlLeak => &[ControlCharacter],
            _ => &[],
        }
    }

    /// Triggering or none-directly.
    pub fn strength(self) -> Strength {
        match self {
            Family::MatraDrop
            | Family::MatraSwap
            | Family::NuktaLoss
            | Family::ViramaDelete
            | Family::RephMisplace
            | Family::OcrConfusion
            | Family::DigitDanda => Strength::NoneDirectly,
            _ => Strength::Triggering,
        }
    }
}

/// What `--family` accepts: one family or the mixture of all of them.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Selection {
    /// A single family.
    Family(Family),
    /// Every family on a disjoint partition of the sites.
    Mixed,
}

impl Selection {
    /// `mixed` or the family name.
    pub fn name(self) -> &'static str {
        match self {
            Selection::Family(f) => f.name(),
            Selection::Mixed => "mixed",
        }
    }
    /// Parse `mixed` or a family name.
    pub fn from_name(name: &str) -> Option<Selection> {
        if name == "mixed" {
            Some(Selection::Mixed)
        } else {
            Family::from_name(name).map(Selection::Family)
        }
    }
}

/// One corrupted site.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Site {
    /// Index of the site's cluster in the clean input.
    pub source: usize,
    /// Index of the cluster in the corrupted output that carries the damage.
    pub cluster: usize,
    /// The family that corrupted it (the real family, also under `mixed`).
    pub family: Family,
    /// The rules this site is expected to trigger; empty when none is expected.
    pub kinds: Vec<IssueKind>,
    /// The text that replaced the clean cluster (empty when the cluster was deleted). Not part of
    /// the sidecar; kept so tests can compare a site across values of `p`.
    pub replacement: String,
}

/// The corrupted text and where it was corrupted.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Corrupted {
    /// The corrupted text.
    pub text: String,
    /// The corrupted sites, in input order.
    pub sites: Vec<Site>,
}

/// Why a `--p` value was refused.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum PError {
    /// Not a decimal in `[0, 1]` with at most six decimals.
    #[error("p must be a decimal between 0 and 1 with at most 6 decimals, got {0:?}")]
    Invalid(String),
}

/// Parse a decimal probability into parts per million: digits, optionally a dot and one to six
/// more digits, with a value in `[0, 1]`. No sign, no exponent, no spaces, no bare `.5` or `5.`.
///
/// # Errors
///
/// [`PError::Invalid`] for anything else.
pub fn parse_p_ppm(s: &str) -> Result<u32, PError> {
    let bad = || PError::Invalid(s.to_owned());
    let (int, frac) = match s.split_once('.') {
        Some((i, f)) => (i, Some(f)),
        None => (s, None),
    };
    let digits = |t: &str| !t.is_empty() && t.bytes().all(|b| b.is_ascii_digit());
    if !digits(int) {
        return Err(bad());
    }
    let mut frac_ppm = 0u32;
    if let Some(f) = frac {
        if !digits(f) || f.len() > 6 {
            return Err(bad());
        }
        // Right-pad to six places: "05" is 50_000.
        for (k, b) in f.bytes().enumerate() {
            frac_ppm += u32::from(b - b'0') * 10u32.pow(5 - k as u32);
        }
    }
    let int: u32 = int.parse().map_err(|_| bad())?;
    let ppm = int
        .checked_mul(1_000_000)
        .and_then(|v| v.checked_add(frac_ppm))
        .ok_or_else(bad)?;
    if ppm > 1_000_000 { Err(bad()) } else { Ok(ppm) }
}

/// The decimal string for a ppm value: `50_000` is `0.05`, `0` is `0`, `1_000_000` is `1`.
pub fn p_label(ppm: u32) -> String {
    let (int, frac) = (ppm / 1_000_000, ppm % 1_000_000);
    if frac == 0 {
        return int.to_string();
    }
    let mut s = format!("{int}.{frac:06}");
    while s.ends_with('0') {
        s.pop();
    }
    s
}

/// SplitMix64 (Vigna) as a pure function of `x`: the generator adds the golden-ratio increment and
/// mixes, so `splitmix64(0)` is the first output of the reference generator seeded 0.
pub fn splitmix64(x: u64) -> u64 {
    let mut z = x.wrapping_add(0x9E37_79B9_7F4A_7C15);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

/// FNV-1a, 64 bits.
pub fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for &b in bytes {
        h ^= u64::from(b);
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
}

/// xorshift64* (Vigna 2014).
struct Rng(u64);

impl Rng {
    fn new(state: u64) -> Rng {
        // The all-zero state is a fixed point of xorshift; splitmix64 makes it vanishingly rare.
        Rng(if state == 0 {
            0x9E37_79B9_7F4A_7C15
        } else {
            state
        })
    }

    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    /// Uniform in `0..n` by rejection sampling (no modulo bias). `n` must be non-zero.
    fn below(&mut self, n: u64) -> u64 {
        let zone = u64::MAX - u64::MAX % n;
        loop {
            let x = self.next();
            if x < zone {
                return x % n;
            }
        }
    }

    fn pick<T: Copy>(&mut self, items: &[T]) -> T {
        items[self.below(items.len() as u64) as usize]
    }

    /// A code point of the Devanagari block drawn by rejection sampling: seven bits per draw, so
    /// adding a code point to a class table changes only the draws that land on it.
    fn devanagari_where(&mut self, accept: impl Fn(char) -> bool) -> char {
        for _ in 0..4096 {
            let cp = 0x0900 + (self.next() >> 57) as u32;
            if let Some(c) = char::from_u32(cp)
                && accept(c)
            {
                return c;
            }
        }
        (0x0900..=0x097F)
            .filter_map(char::from_u32)
            .find(|&c| accept(c))
            .unwrap_or('\u{0900}')
    }
}

/// One planned edit of a site: the replacement text, which byte of it carries the damage the
/// expected rules should see, and what those rules are.
struct Edit {
    text: String,
    marker: usize,
    kinds: &'static [IssueKind],
}

fn is_matra(c: char) -> bool {
    classify(c, 1) == Class::Matra
}

/// Code points of a cluster with their classes (the BOM exemption is irrelevant here).
fn classes(s: &str) -> Vec<(char, Class)> {
    s.chars().map(|c| (c, classify(c, 1))).collect()
}

fn position(cs: &[(char, Class)], class: Class) -> Option<usize> {
    cs.iter().position(|&(_, k)| k == class)
}

fn byte_offset(cs: &[(char, Class)], idx: usize) -> usize {
    cs.iter().take(idx).map(|&(c, _)| c.len_utf8()).sum()
}

fn collect(cs: &[(char, Class)]) -> String {
    cs.iter().map(|&(c, _)| c).collect()
}

fn splice(cs: &[(char, Class)], idx: usize, insert: &[char], remove: usize) -> String {
    let mut out: String = cs.iter().take(idx).map(|&(c, _)| c).collect();
    out.extend(insert);
    out.extend(cs.iter().skip(idx + remove).map(|&(c, _)| c));
    out
}

fn ends_with_virama(cluster: &str) -> bool {
    let cs = classes(cluster);
    matches!(
        cs.as_slice(),
        [.., (_, Class::Virama)] | [.., (_, Class::Virama), (_, Class::Zwj | Class::Zwnj)]
    )
}

fn reph_initial(cs: &[(char, Class)]) -> bool {
    matches!(
        cs,
        [
            ('\u{0930}', _),
            (_, Class::Virama),
            (_, Class::Consonant | Class::NuktaConsonant),
            ..
        ]
    )
}

/// A legacy-font site for the short-i matra: a word-initial syllable that has one, so that moving it
/// in front of its consonant leaves it with nothing to attach to. In the middle of a word it would
/// simply attach to the previous consonant, which no structural rule can see.
fn legacy_short_i(cs: &[(char, Class)], ctx: &Ctx<'_>) -> bool {
    cs.first().map(|c| c.1) == Some(Class::Consonant)
        && cs.iter().any(|&(c, _)| c == SHORT_I)
        && ctx
            .prev()
            .is_none_or(|p| p.chars().all(char::is_whitespace))
}

/// Bengali and Gurmukhi counterparts of a Devanagari matra, where Unicode has one.
fn other_indic_matras(c: char) -> [Option<char>; 2] {
    let cp = c as u32;
    let bengali = match cp {
        0x093E..=0x0940 => Some(cp - 0x093E + 0x09BE),
        0x0941..=0x0943 => Some(cp - 0x0941 + 0x09C1),
        0x0947 | 0x0948 => Some(cp - 0x0947 + 0x09C7),
        0x094B | 0x094C => Some(cp - 0x094B + 0x09CB),
        _ => None,
    };
    let gurmukhi = match cp {
        0x093E..=0x0942 => Some(cp - 0x093E + 0x0A3E),
        0x0947 | 0x0948 => Some(cp - 0x0947 + 0x0A47),
        0x094B | 0x094C => Some(cp - 0x094B + 0x0A4B),
        _ => None,
    };
    [
        bengali.and_then(char::from_u32),
        gurmukhi.and_then(char::from_u32),
    ]
}

const CONFUSIONS: [(char, char); 14] = [
    ('ब', 'व'),
    ('व', 'ब'),
    ('घ', 'ध'),
    ('ध', 'घ'),
    ('भ', 'म'),
    ('म', 'भ'),
    ('ट', 'ढ'),
    ('ढ', 'ट'),
    ('ऱ', 'र'),
    ('र', 'ऱ'),
    ('ड', 'ङ'),
    ('ङ', 'ड'),
    ('य', 'थ'),
    ('थ', 'य'),
];

const VIRAMA: char = '\u{094D}';
const NUKTA: char = '\u{093C}';
const SHORT_I: char = '\u{093F}';
const LEGACY_REPH_PUA: char = '\u{F0D0}';

/// The site under consideration: the clean clusters and which one it is.
struct Ctx<'a> {
    texts: &'a [&'a str],
    i: usize,
}

impl Ctx<'_> {
    fn cur(&self) -> &str {
        self.texts[self.i]
    }
    fn prev(&self) -> Option<&str> {
        self.i.checked_sub(1).map(|p| self.texts[p])
    }
}

/// Is cluster `ctx.i` a site for `family`? Decided from the clean text alone, never from the draw.
fn eligible(family: Family, ctx: &Ctx<'_>) -> bool {
    let cs = classes(ctx.cur());
    let has = |class: Class| cs.iter().any(|&(_, k)| k == class);
    let first = cs.first().map(|&(_, k)| k);
    match family {
        Family::MatraDrop | Family::MatraSwap | Family::MatraDouble | Family::MatraDetach => {
            has(Class::Matra)
        }
        Family::NuktaLoss => has(Class::Nukta),
        Family::NuktaSpurious => {
            (first == Some(Class::Consonant) && !has(Class::Nukta))
                || matches!(first, Some(Class::Vowel | Class::Digit))
        }
        Family::ViramaDelete => cs
            .windows(2)
            .any(|w| w[0].1 == Class::Virama && w[1].1 == Class::Consonant),
        Family::ViramaInsert => {
            has(Class::Matra)
                || matches!(
                    first,
                    Some(Class::Vowel | Class::Consonant | Class::NuktaConsonant)
                )
        }
        Family::BinduSwap => has(Class::Bindu),
        Family::SignOrder => {
            cs.windows(2)
                .any(|w| w[0].1 == Class::Bindu && w[1].1 == Class::Visarga)
                || position(&cs, Class::Matra).is_some_and(|m| {
                    cs[m..]
                        .iter()
                        .any(|&(_, k)| matches!(k, Class::Bindu | Class::Visarga))
                })
        }
        Family::RephMisplace => reph_initial(&cs),
        Family::JoinerInject => ctx.prev().is_none_or(|p| !ends_with_virama(p)),
        Family::LegacyFont => reph_initial(&cs) || legacy_short_i(&cs, ctx) || has(Class::Nukta),
        Family::OcrConfusion => cs
            .first()
            .is_some_and(|&(c, _)| CONFUSIONS.iter().any(|&(from, _)| from == c)),
        Family::WordBoundary => ctx.cur() == " " || has(Class::Matra) || has(Class::Virama),
        Family::DigitDanda => cs.len() == 1 && matches!(first, Some(Class::Digit | Class::Danda)),
        Family::RandomSubstitution => cs
            .iter()
            .any(|&(c, _)| ('\u{0900}'..='\u{097F}').contains(&c)),
        Family::MixedScript => {
            first == Some(Class::Consonant)
                && cs.iter().skip(1).any(|&(_, k)| {
                    matches!(
                        k,
                        Class::Nukta
                            | Class::Virama
                            | Class::Matra
                            | Class::Bindu
                            | Class::Visarga
                            | Class::Vedic
                    )
                })
        }
        Family::ControlLeak => ctx.i >= 1,
    }
}

/// Plan the edit for an eligible site. `rng` is the site's replacement stream.
fn plan(family: Family, ctx: &Ctx<'_>, rng: &mut Rng) -> Edit {
    use IssueKind as K;
    let cs = classes(ctx.cur());
    let at = |idx: usize| byte_offset(&cs, idx);
    let matra = position(&cs, Class::Matra);
    let none: &'static [IssueKind] = &[];
    match family {
        Family::MatraDrop => {
            let m = matra.unwrap_or(0);
            Edit {
                text: splice(&cs, m, &[], 1),
                marker: at(m),
                kinds: none,
            }
        }
        Family::MatraSwap => {
            let m = matra.unwrap_or(0);
            let old = cs[m].0;
            let new = rng.devanagari_where(|c| is_matra(c) && c != old);
            Edit {
                text: splice(&cs, m, &[new], 1),
                marker: at(m),
                kinds: none,
            }
        }
        Family::MatraDouble => {
            let m = matra.unwrap_or(0);
            let second = if rng.below(2) == 0 {
                cs[m].0
            } else {
                rng.devanagari_where(is_matra)
            };
            Edit {
                text: splice(&cs, m + 1, &[second], 0),
                marker: at(m + 1),
                kinds: &[K::DoubleMatra],
            }
        }
        Family::MatraDetach => {
            let m = matra.unwrap_or(0);
            Edit {
                text: splice(&cs, m, &[' '], 0),
                marker: at(m),
                kinds: &[K::DependentVowelWithoutBase],
            }
        }
        Family::NuktaLoss => {
            let n = position(&cs, Class::Nukta).unwrap_or(0);
            Edit {
                text: splice(&cs, n, &[], 1),
                marker: at(n),
                kinds: none,
            }
        }
        Family::NuktaSpurious => {
            if matches!(cs.first().map(|c| c.1), Some(Class::Vowel | Class::Digit)) {
                return Edit {
                    text: splice(&cs, 1, &[NUKTA], 0),
                    marker: at(1),
                    kinds: &[K::NuktaOnNonConsonant],
                };
            }
            // q = 0.3: with a matra present, put the nukta after it instead of after the consonant.
            let late = rng.below(10) < 3;
            match matra {
                Some(m) if late => Edit {
                    text: splice(&cs, m + 1, &[NUKTA], 0),
                    marker: at(m + 1),
                    kinds: &[K::NuktaAfterMatra],
                },
                _ => Edit {
                    text: splice(&cs, 1, &[NUKTA], 0),
                    marker: at(1),
                    kinds: none,
                },
            }
        }
        Family::ViramaDelete => {
            let j = cs
                .windows(2)
                .position(|w| w[0].1 == Class::Virama && w[1].1 == Class::Consonant)
                .unwrap_or(0);
            Edit {
                text: splice(&cs, j, &[], 1),
                marker: at(j),
                kinds: none,
            }
        }
        Family::ViramaInsert => {
            if let Some(m) = matra {
                Edit {
                    text: splice(&cs, m + 1, &[VIRAMA], 0),
                    marker: at(m + 1),
                    kinds: &[K::ViramaAfterMatra],
                }
            } else if cs.first().map(|c| c.1) == Some(Class::Vowel) {
                Edit {
                    text: splice(&cs, 1, &[VIRAMA], 0),
                    marker: at(1),
                    kinds: &[K::ViramaWithoutConsonant],
                }
            } else {
                // After the last consonant (and its nukta): one virama is valid, the second is not.
                let pos = cs
                    .iter()
                    .rposition(|&(_, k)| {
                        matches!(k, Class::Consonant | Class::NuktaConsonant | Class::Nukta)
                    })
                    .map_or(1, |p| p + 1);
                Edit {
                    text: splice(&cs, pos, &[VIRAMA, VIRAMA], 0),
                    marker: at(pos) + VIRAMA.len_utf8(),
                    kinds: &[K::ViramaWithoutConsonant],
                }
            }
        }
        Family::BinduSwap => {
            let b = position(&cs, Class::Bindu).unwrap_or(0);
            let other = if cs[b].0 == '\u{0902}' {
                '\u{0901}'
            } else {
                '\u{0902}'
            };
            // q = 0.2: keep both signs.
            if rng.below(5) == 0 {
                Edit {
                    text: splice(&cs, b + 1, &[other], 0),
                    marker: at(b + 1),
                    kinds: &[K::MultipleAnusvaraLike],
                }
            } else {
                Edit {
                    text: splice(&cs, b, &[other], 1),
                    marker: at(b),
                    kinds: none,
                }
            }
        }
        Family::SignOrder => {
            if let Some(j) = cs
                .windows(2)
                .position(|w| w[0].1 == Class::Bindu && w[1].1 == Class::Visarga)
            {
                let mut swapped = cs.clone();
                swapped.swap(j, j + 1);
                Edit {
                    text: collect(&swapped),
                    marker: at(j),
                    kinds: &[K::VisargaBeforeAnusvara],
                }
            } else {
                let m = matra.unwrap_or(0);
                let s = cs
                    .iter()
                    .enumerate()
                    .skip(m)
                    .find(|&(_, &(_, k))| matches!(k, Class::Bindu | Class::Visarga))
                    .map_or(m, |(s, _)| s);
                let mut moved = cs.clone();
                let sign = moved.remove(s);
                moved.insert(m, sign);
                Edit {
                    text: collect(&moved),
                    marker: at(m),
                    kinds: &[K::SignBeforeMatra],
                }
            }
        }
        Family::RephMisplace => {
            let mut v = cs.clone();
            let text = if rng.below(2) == 0 {
                // र् C ... -> C् र ...: move the reph behind the consonant.
                v.swap(0, 2);
                collect(&v)
            } else {
                // र् C ... -> र C ...: drop the virama.
                splice(&cs, 1, &[], 1)
            };
            Edit {
                text,
                marker: 0,
                kinds: none,
            }
        }
        Family::JoinerInject => {
            let joiner = rng.pick(&['\u{200D}', '\u{200C}']);
            Edit {
                text: format!("{joiner}{}", ctx.cur()),
                marker: 0,
                kinds: &[K::ZwjZwnjMisplaced],
            }
        }
        Family::LegacyFont => {
            if reph_initial(&cs) {
                // The reph is stored after its syllable in a legacy font and converts to a
                // private-use glyph code.
                let mut text = splice(&cs, 0, &[], 2);
                let marker = text.len();
                text.push(LEGACY_REPH_PUA);
                Edit {
                    text,
                    marker,
                    kinds: &[K::UnexpectedCodePoint],
                }
            } else if legacy_short_i(&cs, ctx) {
                // Visual order: the short-i matra is stored before its consonant.
                let i = cs.iter().position(|&(c, _)| c == SHORT_I).unwrap_or(0);
                let mut text = String::from(SHORT_I);
                text.push_str(&splice(&cs, i, &[], 1));
                Edit {
                    text,
                    marker: 0,
                    kinds: &[K::DependentVowelWithoutBase],
                }
            } else {
                let n = position(&cs, Class::Nukta).unwrap_or(0);
                Edit {
                    text: splice(&cs, n, &[], 1),
                    marker: at(n),
                    kinds: none,
                }
            }
        }
        Family::OcrConfusion => {
            let from = cs[0].0;
            let to = CONFUSIONS
                .iter()
                .find(|&&(f, _)| f == from)
                .map_or(from, |&(_, t)| t);
            Edit {
                text: splice(&cs, 0, &[to], 1),
                marker: 0,
                kinds: none,
            }
        }
        Family::WordBoundary => {
            if ctx.cur() == " " {
                return Edit {
                    text: String::new(),
                    marker: 0,
                    kinds: none,
                };
            }
            let virama = position(&cs, Class::Virama);
            let use_matra = match (matra, virama) {
                (Some(_), Some(_)) => rng.below(2) == 0,
                (Some(_), None) => true,
                _ => false,
            };
            if use_matra {
                let m = matra.unwrap_or(0);
                Edit {
                    text: splice(&cs, m, &[' '], 0),
                    marker: at(m),
                    kinds: &[K::DependentVowelWithoutBase],
                }
            } else {
                let v = virama.unwrap_or(0);
                Edit {
                    text: splice(&cs, v, &[' '], 0),
                    marker: at(v) + 1,
                    kinds: &[K::ViramaWithoutConsonant],
                }
            }
        }
        Family::DigitDanda => {
            let c = cs[0].0;
            let text = match c as u32 {
                0x0965 => "\u{0964}\u{0964}".to_owned(),
                0x0964 => rng.pick(&['|', '1']).to_string(),
                d => {
                    let ascii = char::from_u32(0x30 + (d - 0x0966)).unwrap_or('0');
                    rng.pick(&[ascii, '\u{0964}', '|']).to_string()
                }
            };
            Edit {
                text,
                marker: 0,
                kinds: none,
            }
        }
        Family::RandomSubstitution => {
            let spots: Vec<usize> = cs
                .iter()
                .enumerate()
                .filter(|&(_, &(c, _))| ('\u{0900}'..='\u{097F}').contains(&c))
                .map(|(i, _)| i)
                .collect();
            let j = spots[rng.below(spots.len() as u64) as usize];
            let old = cs[j].0;
            let new = rng.devanagari_where(|c| c != old);
            Edit {
                text: splice(&cs, j, &[new], 1),
                marker: at(j),
                kinds: none,
            }
        }
        Family::MixedScript => {
            let other_matra = if rng.below(2) == 1 { matra } else { None }.and_then(|m| {
                let options: Vec<char> =
                    other_indic_matras(cs[m].0).into_iter().flatten().collect();
                if options.is_empty() {
                    None
                } else {
                    Some((m, options[rng.below(options.len() as u64) as usize]))
                }
            });
            match other_matra {
                Some((m, replacement)) => Edit {
                    text: splice(&cs, m, &[replacement], 1),
                    marker: at(m),
                    kinds: &[K::MixedScriptInCluster],
                },
                None => {
                    let latin = rng.pick(&['A', 'e', 'o']);
                    Edit {
                        text: splice(&cs, 0, &[latin], 1),
                        marker: at(1),
                        kinds: &[K::MixedScriptInCluster],
                    }
                }
            }
        }
        Family::ControlLeak => {
            let ch = rng.pick(&['\u{FEFF}', '\u{200E}', '\u{202E}', '\u{0007}']);
            Edit {
                text: format!("{ch}{}", ctx.cur()),
                marker: 0,
                kinds: &[K::ControlCharacter],
            }
        }
    }
}

/// Is site `i` selected at `p_ppm`? `u` is the site's first draw.
fn selected(u: u64, p_ppm: u32) -> bool {
    ((u128::from(u >> 11) * 1_000_000) >> 53) < u128::from(p_ppm)
}

/// Corrupt `clean` with `selection` at probability `p_ppm` (parts per million) and `seed`.
///
/// `p_ppm == 0` returns `clean` unchanged. The same arguments always give the same output.
pub fn corrupt(clean: &str, selection: Selection, p_ppm: u32, seed: u64) -> Corrupted {
    let texts: Vec<&str> = clean.graphemes(true).collect();
    let label = fnv1a64(selection.name().as_bytes());
    let mut out = String::with_capacity(clean.len() + clean.len() / 8);
    let mut pending: Vec<(usize, usize, Family, Edit)> = Vec::new();
    for (i, &text) in texts.iter().enumerate() {
        let family = match selection {
            Selection::Family(f) => f,
            Selection::Mixed => {
                Family::ALL[(splitmix64(seed ^ i as u64) % Family::ALL.len() as u64) as usize]
            }
        };
        let ctx = Ctx { texts: &texts, i };
        if p_ppm == 0 || !eligible(family, &ctx) {
            out.push_str(text);
            continue;
        }
        let base = splitmix64(seed ^ label ^ i as u64);
        if !selected(Rng::new(base).next(), p_ppm) {
            out.push_str(text);
            continue;
        }
        let mut rng = Rng::new(splitmix64(base ^ 1));
        let edit = plan(family, &ctx, &mut rng);
        let start = out.len();
        out.push_str(&edit.text);
        pending.push((i, start + edit.marker, family, edit));
    }

    // Map each marker byte to the cluster of the *output* that contains it.
    let starts: Vec<usize> = out.grapheme_indices(true).map(|(s, _)| s).collect();
    let sites = pending
        .into_iter()
        .map(|(source, marker, family, edit)| Site {
            source,
            cluster: starts.partition_point(|&s| s <= marker).saturating_sub(1),
            family,
            kinds: edit.kinds.to_vec(),
            replacement: edit.text,
        })
        .collect();
    Corrupted { text: out, sites }
}

#[derive(Serialize)]
struct SidecarSite<'a> {
    source: usize,
    cluster: usize,
    family: &'static str,
    kinds: &'a [IssueKind],
}

#[derive(Serialize)]
struct Sidecar<'a> {
    family: &'static str,
    seed: u64,
    p_ppm: u32,
    sites: Vec<SidecarSite<'a>>,
}

/// The `.sites.json` sidecar for a corruption run, as compact JSON: the selection, the seed, `p`
/// in ppm, and for each corrupted site the clean cluster index, the output cluster index, the real
/// family and the rules the site is expected to trigger.
pub fn sites_json(selection: Selection, seed: u64, p_ppm: u32, corrupted: &Corrupted) -> String {
    let sidecar = Sidecar {
        family: selection.name(),
        seed,
        p_ppm,
        sites: corrupted
            .sites
            .iter()
            .map(|s| SidecarSite {
                source: s.source,
                cluster: s.cluster,
                family: s.family.name(),
                kinds: &s.kinds,
            })
            .collect(),
    };
    serde_json::to_string(&sidecar).expect("sidecar serialisation is infallible")
}
