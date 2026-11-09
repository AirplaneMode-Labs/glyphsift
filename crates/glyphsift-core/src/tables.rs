//! Code-point tables for the Devanagari validator (`docs/devanagari-rules.md` section 2).
//!
//! Every table is a sorted `const` slice of inclusive `(first, last)` ranges that do not overlap,
//! looked up by binary search. The unit tests prove each table is sorted and non-overlapping, so a
//! range added out of order fails a test instead of silently misclassifying a code point.

use unicode_general_category::{GeneralCategory, get_general_category};

/// What a code point is, for the purposes of the cluster grammar.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Class {
    /// `U+0915..U+0939`, `U+0978..U+097F`.
    Consonant,
    /// `U+0958..U+095F`: a consonant that already carries a nukta (composition exclusions).
    NuktaConsonant,
    /// `U+093C`.
    Nukta,
    /// `U+094D`.
    Virama,
    /// A dependent vowel sign.
    Matra,
    /// Anusvara, chandrabindu, inverted chandrabindu (`U+0900..U+0902`).
    Bindu,
    /// `U+0903`.
    Visarga,
    /// An independent vowel letter.
    Vowel,
    /// `U+0966..U+096F`.
    Digit,
    /// `U+0964`, `U+0965`.
    Danda,
    /// `U+093D`.
    Avagraha,
    /// `U+0950`.
    Om,
    /// `U+0951..U+0954`.
    Vedic,
    /// `U+0970`, `U+0971`.
    Abbrev,
    /// `U+200D`.
    Zwj,
    /// `U+200C`.
    Zwnj,
    /// TAB, LF, CR, and a BOM at byte offset 0.
    AllowedControl,
    /// A control that is flagged: other C0/C1, bidi controls, a BOM after offset 0.
    Control,
    /// U+FFFD, private use, unassigned, noncharacters, unlisted Devanagari-block code points.
    Unexpected,
    /// A base letter (`L*`) outside the Devanagari blocks.
    OtherLetter,
    /// A combining mark from an Indic block other than Devanagari (`U+0980..U+0DFF`).
    OtherMark,
    /// Everything else: spaces, punctuation, symbols, emoji, other-script non-letters.
    Plain,
}

type Range = (u32, u32);
type ClassRange = (u32, u32, Class);

/// The Devanagari block, `U+0900..U+097F`, row by row. Together with `JOINERS` these are the only
/// code points in the block that are not `Unexpected`; the block has no gaps in this table.
const DEVANAGARI: &[ClassRange] = &[
    (0x0900, 0x0902, Class::Bindu),
    (0x0903, 0x0903, Class::Visarga),
    (0x0904, 0x0914, Class::Vowel),
    (0x0915, 0x0939, Class::Consonant),
    (0x093A, 0x093B, Class::Matra),
    (0x093C, 0x093C, Class::Nukta),
    (0x093D, 0x093D, Class::Avagraha),
    (0x093E, 0x094C, Class::Matra),
    (0x094D, 0x094D, Class::Virama),
    (0x094E, 0x094F, Class::Matra),
    (0x0950, 0x0950, Class::Om),
    (0x0951, 0x0954, Class::Vedic),
    (0x0955, 0x0957, Class::Matra),
    (0x0958, 0x095F, Class::NuktaConsonant),
    (0x0960, 0x0961, Class::Vowel),
    (0x0962, 0x0963, Class::Matra),
    (0x0964, 0x0965, Class::Danda),
    (0x0966, 0x096F, Class::Digit),
    (0x0970, 0x0971, Class::Abbrev),
    (0x0972, 0x0977, Class::Vowel),
    (0x0978, 0x097F, Class::Consonant),
];

/// Controls that are flagged: C0 and C1 except TAB, LF and CR, plus the bidi format controls
/// (`U+200E`, `U+200F`, `U+202A..U+202E`, `U+2066..U+2069`). `U+FEFF` is handled by offset.
const CONTROL: &[Range] = &[
    (0x0000, 0x0008),
    (0x000B, 0x000C),
    (0x000E, 0x001F),
    (0x007F, 0x009F),
    (0x200E, 0x200F),
    (0x202A, 0x202E),
    (0x2066, 0x2069),
];

/// Code points flagged as unexpected whatever their general category: Devanagari Extended,
/// private use, noncharacters in the Arabic Presentation block, U+FFFD, Devanagari Extended-A and
/// the supplementary private use planes. (Other noncharacters, `U+xFFFE` and `U+xFFFF`, are
/// checked by mask; unassigned code points by general category.)
const UNEXPECTED: &[Range] = &[
    (0xA8E0, 0xA8FF),
    (0xE000, 0xF8FF),
    (0xFDD0, 0xFDEF),
    (0xFFFD, 0xFFFD),
    (0x11B00, 0x11B5F),
    (0xF0000, 0x10FFFF),
];

/// Indic blocks other than Devanagari whose combining marks count as "other script" marks:
/// Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada, Malayalam, Sinhala.
const OTHER_INDIC: &[Range] = &[(0x0980, 0x0DFF)];

const BOM: u32 = 0xFEFF;

fn in_ranges(table: &[Range], cp: u32) -> bool {
    table
        .binary_search_by(|&(lo, hi)| {
            if hi < cp {
                core::cmp::Ordering::Less
            } else if lo > cp {
                core::cmp::Ordering::Greater
            } else {
                core::cmp::Ordering::Equal
            }
        })
        .is_ok()
}

fn lookup(table: &[ClassRange], cp: u32) -> Option<Class> {
    table
        .binary_search_by(|&(lo, hi, _)| {
            if hi < cp {
                core::cmp::Ordering::Less
            } else if lo > cp {
                core::cmp::Ordering::Greater
            } else {
                core::cmp::Ordering::Equal
            }
        })
        .ok()
        .map(|i| table[i].2)
}

/// Classify `c`, which starts at byte `offset` of the whole input (a BOM is only valid at 0).
pub(crate) fn classify(c: char, offset: usize) -> Class {
    let cp = c as u32;
    if let Some(class) = lookup(DEVANAGARI, cp) {
        return class;
    }
    match cp {
        0x200C => return Class::Zwnj,
        0x200D => return Class::Zwj,
        0x0009 | 0x000A | 0x000D => return Class::AllowedControl,
        BOM => {
            return if offset == 0 {
                Class::AllowedControl
            } else {
                Class::Control
            };
        }
        _ => {}
    }
    if in_ranges(CONTROL, cp) {
        return Class::Control;
    }
    // U+xFFFE and U+xFFFF are noncharacters in every plane.
    if in_ranges(UNEXPECTED, cp) || cp & 0xFFFE == 0xFFFE {
        return Class::Unexpected;
    }
    match get_general_category(c) {
        GeneralCategory::Unassigned => Class::Unexpected,
        GeneralCategory::UppercaseLetter
        | GeneralCategory::LowercaseLetter
        | GeneralCategory::TitlecaseLetter
        | GeneralCategory::ModifierLetter
        | GeneralCategory::OtherLetter => Class::OtherLetter,
        GeneralCategory::NonspacingMark
        | GeneralCategory::SpacingMark
        | GeneralCategory::EnclosingMark
            if in_ranges(OTHER_INDIC, cp) =>
        {
            Class::OtherMark
        }
        _ => Class::Plain,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sorted_and_disjoint(table: &[Range]) {
        for r in table {
            assert!(r.0 <= r.1, "inverted range {r:x?}");
        }
        for w in table.windows(2) {
            assert!(w[0].1 < w[1].0, "ranges overlap or are unsorted: {:x?}", w);
        }
    }

    #[test]
    fn tables_are_sorted_and_disjoint() {
        let dev: Vec<Range> = DEVANAGARI.iter().map(|&(a, b, _)| (a, b)).collect();
        sorted_and_disjoint(&dev);
        sorted_and_disjoint(CONTROL);
        sorted_and_disjoint(UNEXPECTED);
        sorted_and_disjoint(OTHER_INDIC);
    }

    #[test]
    fn the_devanagari_block_has_no_gaps() {
        assert_eq!(DEVANAGARI.first().map(|r| r.0), Some(0x0900));
        assert_eq!(DEVANAGARI.last().map(|r| r.1), Some(0x097F));
        for w in DEVANAGARI.windows(2) {
            assert_eq!(
                w[0].1 + 1,
                w[1].0,
                "gap between {:x?} and {:x?}",
                w[0],
                w[1]
            );
        }
    }

    #[test]
    fn spot_checks_against_the_rules_doc() {
        assert_eq!(classify('क', 5), Class::Consonant);
        assert_eq!(classify('\u{0958}', 5), Class::NuktaConsonant);
        assert_eq!(classify('\u{093F}', 5), Class::Matra);
        assert_eq!(classify('\u{0950}', 5), Class::Om);
        assert_eq!(classify('\u{200D}', 5), Class::Zwj);
        assert_eq!(classify('\u{000B}', 5), Class::Control);
        assert_eq!(classify('\u{0009}', 5), Class::AllowedControl);
        assert_eq!(classify('\u{FEFF}', 0), Class::AllowedControl);
        assert_eq!(classify('\u{FEFF}', 3), Class::Control);
        assert_eq!(classify('\u{FFFD}', 0), Class::Unexpected);
        assert_eq!(classify('\u{F0D0}', 0), Class::Unexpected);
        assert_eq!(classify('\u{0378}', 0), Class::Unexpected);
        assert_eq!(classify('\u{FFFF}', 0), Class::Unexpected);
        assert_eq!(classify('\u{10FFFF}', 0), Class::Unexpected);
        assert_eq!(classify('A', 0), Class::OtherLetter);
        assert_eq!(classify('\u{0B95}', 0), Class::OtherLetter);
        assert_eq!(classify('\u{09BE}', 0), Class::OtherMark);
        assert_eq!(classify(' ', 0), Class::Plain);
        assert_eq!(classify('\u{1F64F}', 0), Class::Plain);
        assert_eq!(classify('\u{0301}', 0), Class::Plain);
    }
}
