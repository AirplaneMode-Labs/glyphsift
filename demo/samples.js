// Synthetic sample texts for the demo. None is taken from a real document.
// Invisible or detached marks are written as \uXXXX escapes, as in
// crates/glyphsift-core/tests/cases/devanagari.toml.

export const SAMPLES = {
  // Well-formed: namaste + danda. Four clusters; the conjunct स्ते is one (GB9c).
  clean: {
    label: "Clean",
    text: "नमस्ते।",
    // No notice: nothing is wrong with this text.
    defect: false,
  },
  // Typical OCR artefacts, each from a case in the table:
  //   ो at the start of a word (matra_at_start_of_word),
  //   ा twice on one consonant (double matra),
  //   ं on its own (stray anusvara),
  //   ि separated from its consonant by a space (matra_after_space_in_sentence).
  ocr: {
    label: "OCR-corrupted",
    text: "ोम काा ं नमस्ते िदुनिया",
    defect: true,
  },
  // Devanagari typed in a legacy 8-bit Hindi font and read back as Latin: the bytes decode to
  // letters that look like gibberish. Synthetic pattern, no real document.
  legacy: {
    label: "Legacy-font gibberish",
    text: "ueLdkj nqfu;k! ;g ,d uewuk gSA",
    defect: true,
  },
};
