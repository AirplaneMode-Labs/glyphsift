// Synthetic sample texts for the demo. None is taken from a real document.
// Defects, invisible marks and detached marks are written as \uXXXX escapes, as in
// crates/glyphsift-core/tests/cases/devanagari.toml, so the source is readable without a
// Devanagari-aware editor.

export const SAMPLES = {
  // Well-formed Hindi: three lines, no rule fires, the score is exactly 1.0000.
  clean: {
    label: "Clean",
    text: [
      "नमस्ते दुनिया।",
      "आज मौसम बहुत अच्छा है।",
      "कृपया दरवाज़ा बंद कर दीजिए।".replace("़ा", "़ा"),
      "",
    ].join("\n"),
    note: "A clean text: no rule fires, so the score is 1.0000.",
  },
  // Typical OCR artefacts, each from a case in the table: a matra at the start of a word, a doubled
  // matra, a stray anusvara, a matra detached by a space, signs before the matra, a matra on a dead
  // consonant, a virama on a vowel. Two clean lines in between show the per-line scores differ.
  ocr: {
    label: "OCR-corrupted",
    text: [
      "आज मौसम बहुत अच्छा है।",
      "ोम काा ं नमस्ते िदुनिया",
      "कृपया बंद कर दीजिए।",
      "कंा कःि क्ा अ्क",
      "",
    ].join("\n"),
    note: "OCR artefacts: the damaged lines score low, the clean lines score 1.0000, and the document score is the average over clusters.",
  },
  // Devanagari typed in a legacy 8-bit Hindi font and read back as Latin letters. To the validator
  // this is ordinary Latin text, so it scores 1.0000: a documented blind spot, not a clean text.
  legacy: {
    label: "Legacy font read as Latin",
    text: "ueLdkj nqfu;k! ;g ,d uewuk gSA\n",
    note: "Legacy-font gibberish decoded as Latin letters. glyphsift only checks Devanagari structure, so this scores 1.0000 even though it is unusable: structural checks cannot see it.",
  },
  // The same font converted to Unicode without a mapping: glyph codes land in the private use area.
  residue: {
    label: "Legacy font residue",
    text: "क\u{F0D0}म \u{F0D1}\u{F0D2} िकताब नमस्ते\n",
    note: "Legacy-font glyph codes converted without a mapping land in the private use area (unexpected_code_point) and the short-i matra comes before its consonant (dependent_vowel_without_base).",
  },
  // Hostile input: a 60-mark run, mixed scripts, controls, joiners, replacement and private-use code
  // points, a virama and nukta soup, CRLF and a BOM in the middle of the text.
  adversarial: {
    label: "Adversarial",
    text: [
      "क" + "ा".repeat(60),
      "Aा eं oि কা க्",
      "क\u0007ख \u{202E}ग \u{FEFF}घ",
      "क\u{200D}क \u{200C}ख क्\u{200D}ष",
      "\u{FFFD} \u{F0D0} \u{E000} \u{378}",
      "़््ँ १़ अा",
      "सामान्य पंक्ति।",
      "",
    ].join("\r\n"),
    note: "Adversarial input: a 60-mark run, mixed scripts, controls, joiners and private-use code points. The validator reports every one and never fails.",
  },
};
