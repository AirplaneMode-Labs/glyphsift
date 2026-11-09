//! The cluster grammar and the sixteen rules (`docs/devanagari-rules.md` sections 3 and 4).
//!
//! `parse` walks one grapheme cluster once, code point by code point, and records for each code
//! point what it attaches to (`Host`) and what the cluster has already seen. Each rule is then a
//! small pure predicate over one `Slot`, so a rule can be read, tested and enabled on its own. A
//! cluster is processed in time linear in its length: no rule looks backwards or forwards beyond
//! the counters `parse` carries.

use crate::report::IssueKind;
use crate::tables::{Class, classify};

/// What the marks that follow attach to.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Host {
    /// Nothing yet: the cluster starts with a combining mark.
    None,
    /// A live consonant (possibly with a nukta, matra or signs already).
    Consonant,
    /// A dead consonant: a consonant followed by a virama (and optionally ZWJ or ZWNJ).
    Dead,
    /// An independent vowel letter.
    Vowel,
    /// A base that cannot carry Devanagari marks: space, digit, danda, other-script letter, ...
    Plain,
}

/// One code point of a cluster together with the state the parser was in just before it.
#[derive(Debug, Clone, Copy)]
pub(crate) struct Slot {
    pub cp: char,
    pub class: Class,
    /// Class of the code point directly before this one in the cluster.
    pub prev: Option<Class>,
    pub host: Host,
    /// Matras seen since the current host started.
    pub matras_before: u32,
    /// Bindus (anusvara, chandrabindu) seen since the current host started.
    pub bindus_before: u32,
    pub visarga_before: bool,
    /// Nuktas seen on the current consonant, counting the implicit one of `U+0958..U+095F`.
    pub nuktas_before: u32,
    /// A bindu or visarga seen since the current host started.
    pub signs_before: bool,
}

/// Fill `slots` with the parse of `cluster`, which starts at byte `start` of the whole input.
pub(crate) fn parse(cluster: &str, start: usize, slots: &mut Vec<Slot>) {
    slots.clear();
    let mut host = Host::None;
    let mut prev: Option<Class> = None;
    let mut matras = 0u32;
    let mut bindus = 0u32;
    let mut nuktas = 0u32;
    let mut visarga = false;
    let mut signs = false;
    for (i, cp) in cluster.char_indices() {
        let class = classify(cp, start + i);
        slots.push(Slot {
            cp,
            class,
            prev,
            host,
            matras_before: matras,
            bindus_before: bindus,
            visarga_before: visarga,
            nuktas_before: nuktas,
            signs_before: signs,
        });
        match class {
            Class::Consonant | Class::NuktaConsonant => {
                host = Host::Consonant;
                matras = 0;
                bindus = 0;
                nuktas = u32::from(class == Class::NuktaConsonant);
                visarga = false;
                signs = false;
            }
            Class::Vowel => {
                host = Host::Vowel;
                matras = 0;
                bindus = 0;
                nuktas = 0;
                visarga = false;
                signs = false;
            }
            Class::Nukta => nuktas = nuktas.saturating_add(1),
            Class::Virama => {
                // A virama makes a dead consonant when it follows a consonant (or consonant and
                // nukta); after a matra it is flagged but still ends the syllable's vowel slot.
                let after_consonant = match prev {
                    Some(Class::Consonant | Class::NuktaConsonant) => true,
                    Some(Class::Nukta) => host == Host::Consonant,
                    Some(Class::Matra) => host == Host::Consonant,
                    _ => false,
                };
                if after_consonant {
                    host = Host::Dead;
                }
            }
            Class::Matra => matras = matras.saturating_add(1),
            Class::Bindu => {
                bindus = bindus.saturating_add(1);
                signs = true;
            }
            Class::Visarga => {
                visarga = true;
                signs = true;
            }
            Class::Vedic | Class::Zwj | Class::Zwnj => {}
            _ => {
                host = Host::Plain;
                matras = 0;
                bindus = 0;
                nuktas = 0;
                visarga = false;
                signs = false;
            }
        }
        prev = Some(class);
    }
}

/// Run the rules over one cluster; `found` receives `(kind, code point)` in code-point order, and
/// for one code point in rule order (the declaration order of `IssueKind`). `slots` is scratch
/// space reused across clusters.
pub(crate) fn check_cluster(
    cluster: &str,
    start: usize,
    slots: &mut Vec<Slot>,
    found: &mut Vec<(IssueKind, char)>,
) {
    found.clear();
    parse(cluster, start, slots);
    // Rule 14 is exclusive: a mixed-script cluster reports its root cause and nothing else.
    if let Some(i) = mixed_script_hook(slots) {
        found.push((IssueKind::MixedScriptInCluster, slots[i].cp));
        return;
    }
    for slot in slots.iter() {
        for &(kind, rule) in RULES {
            if rule(slot) {
                found.push((kind, slot.cp));
            }
        }
    }
}

/// Rule 1. A matra whose preceding code point is not a live consonant: at cluster start, after a
/// space, digit, danda or sign, or after a dead consonant (consonant, virama, optional joiner).
fn dependent_vowel_without_base(s: &Slot) -> bool {
    s.class == Class::Matra
        && s.matras_before == 0
        && matches!(s.host, Host::None | Host::Dead | Host::Plain)
}

/// Rule 2. A bindu, visarga, nukta or Vedic sign with no base in its cluster: at cluster start, or
/// after a space or another base that cannot carry it. A dead consonant cannot carry a bindu or
/// visarga either; it may carry Vedic signs.
fn stray_combining_mark(s: &Slot) -> bool {
    match s.class {
        Class::Nukta => s.host == Host::None,
        Class::Bindu | Class::Visarga => matches!(s.host, Host::None | Host::Plain | Host::Dead),
        Class::Vedic => matches!(s.host, Host::None | Host::Plain),
        _ => false,
    }
}

/// Rule 3. A second (or later) matra in the cluster.
fn double_matra(s: &Slot) -> bool {
    s.class == Class::Matra && s.matras_before > 0
}

/// Rule 4. A second nukta on the same consonant, counting the implicit nukta of `U+0958..U+095F`.
/// A nukta after a matra or sign is `nukta_after_matra` instead.
fn double_nukta(s: &Slot) -> bool {
    s.class == Class::Nukta
        && s.host == Host::Consonant
        && s.nuktas_before > 0
        && s.matras_before == 0
        && !s.signs_before
}

/// Rule 5. A nukta after a matra, bindu or visarga instead of directly after its consonant.
fn nukta_after_matra(s: &Slot) -> bool {
    s.class == Class::Nukta && s.host == Host::Consonant && (s.matras_before > 0 || s.signs_before)
}

/// Rule 6. A nukta on a base that exists but is not a live consonant: an independent vowel, digit,
/// danda or other sign, or directly after a virama.
fn nukta_on_non_consonant(s: &Slot) -> bool {
    s.class == Class::Nukta && matches!(s.host, Host::Vowel | Host::Plain | Host::Dead)
}

/// A virama is well placed directly after a consonant, or after a consonant's nukta.
fn virama_follows_consonant(s: &Slot) -> bool {
    match s.prev {
        Some(Class::Consonant | Class::NuktaConsonant) => true,
        Some(Class::Nukta) => s.host == Host::Consonant,
        _ => false,
    }
}

/// Rule 7. A virama with no consonant directly before it: at cluster start, after a vowel, after
/// another virama, after a nukta that is not on a consonant, or after a sign. (After a matra it is
/// `virama_after_matra`, rule 8.)
fn virama_without_consonant(s: &Slot) -> bool {
    s.class == Class::Virama && !virama_follows_consonant(s) && s.prev != Some(Class::Matra)
}

/// Rule 8. A virama directly after a matra: the syllable already has its vowel.
fn virama_after_matra(s: &Slot) -> bool {
    s.class == Class::Virama && s.prev == Some(Class::Matra)
}

/// Rule 9. A bindu or visarga followed by a matra in the same cluster (the matra comes first).
fn sign_before_matra(s: &Slot) -> bool {
    s.class == Class::Matra && s.signs_before
}

/// Rule 10. A second (or later) anusvara, chandrabindu or inverted chandrabindu.
fn multiple_anusvara_like(s: &Slot) -> bool {
    s.class == Class::Bindu && s.bindus_before > 0
}

/// Rule 11. A bindu after a visarga (the accepted order is bindu, then visarga).
fn visarga_before_anusvara(s: &Slot) -> bool {
    s.class == Class::Bindu && s.visarga_before
}

/// Rule 12. A matra attached to an independent vowel letter.
fn vowel_sign_on_independent_vowel(s: &Slot) -> bool {
    s.class == Class::Matra && s.host == Host::Vowel && s.matras_before == 0
}

/// Rule 13. ZWJ or ZWNJ anywhere other than directly after a virama.
fn zwj_zwnj_misplaced(s: &Slot) -> bool {
    matches!(s.class, Class::Zwj | Class::Zwnj) && s.prev != Some(Class::Virama)
}

/// Rule 14, cluster level. Returns the index of the code point that makes the cluster mixed: a
/// Devanagari mark on a base letter from another script, or a mark from another Indic block on a
/// Devanagari base.
fn mixed_script_position(slots: &[Slot]) -> Option<usize> {
    let first = slots.first()?.class;
    let devanagari_mark = |c: Class| {
        matches!(
            c,
            Class::Nukta
                | Class::Virama
                | Class::Matra
                | Class::Bindu
                | Class::Visarga
                | Class::Vedic
        )
    };
    match first {
        Class::OtherLetter => slots.iter().position(|s| devanagari_mark(s.class)),
        Class::Consonant
        | Class::NuktaConsonant
        | Class::Vowel
        | Class::Digit
        | Class::Danda
        | Class::Avagraha
        | Class::Om
        | Class::Abbrev => slots.iter().position(|s| s.class == Class::OtherMark),
        _ => None,
    }
}

fn mixed_script_hook(slots: &[Slot]) -> Option<usize> {
    mixed_script_position(slots)
}

/// Rule 15. U+FFFD, private use, unassigned, noncharacters, or a code point of a Devanagari block
/// that has no role in the tables.
fn unexpected_code_point(s: &Slot) -> bool {
    s.class == Class::Unexpected
}

/// Rule 16. A control other than TAB, LF and CR, a bidi format control, or a BOM after offset 0.
fn control_character(s: &Slot) -> bool {
    s.class == Class::Control
}

type Rule = (IssueKind, fn(&Slot) -> bool);

/// The slot-level rules in declaration order of `IssueKind` (rule 14 is cluster level).
const RULES: &[Rule] = &[
    (
        IssueKind::DependentVowelWithoutBase,
        dependent_vowel_without_base,
    ),
    (IssueKind::StrayCombiningMark, stray_combining_mark),
    (IssueKind::DoubleMatra, double_matra),
    (IssueKind::DoubleNukta, double_nukta),
    (IssueKind::NuktaAfterMatra, nukta_after_matra),
    (IssueKind::NuktaOnNonConsonant, nukta_on_non_consonant),
    (IssueKind::ViramaWithoutConsonant, virama_without_consonant),
    (IssueKind::ViramaAfterMatra, virama_after_matra),
    (IssueKind::SignBeforeMatra, sign_before_matra),
    (IssueKind::MultipleAnusvaraLike, multiple_anusvara_like),
    (IssueKind::VisargaBeforeAnusvara, visarga_before_anusvara),
    (
        IssueKind::VowelSignOnIndependentVowel,
        vowel_sign_on_independent_vowel,
    ),
    (IssueKind::ZwjZwnjMisplaced, zwj_zwnj_misplaced),
    (IssueKind::UnexpectedCodePoint, unexpected_code_point),
    (IssueKind::ControlCharacter, control_character),
];
