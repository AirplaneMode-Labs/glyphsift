"""Type stubs for the glyphsift Python wheel (release candidate 0.1.3, not tagged).

The extension is a thin wrapper over glyphsift-core: every function takes `str` and returns plain
Python values. The report is canonical JSON, byte-identical to `glyphsift check` and to the WASM build
for valid Unicode text. A lone surrogate cannot be encoded: every function raises ``UnicodeEncodeError``
for one (WASM/JS substitutes U+FFFD and reports ``unexpected_code_point``; the CLI refuses invalid UTF-8
with exit 1).
"""

def validate(text: str) -> str:
    """Validate Devanagari text and return the canonical JSON report (``glyphsift.report/0.2``).

    The text is split into UAX #29 extended grapheme clusters and checked by sixteen structural
    rules. Parse the result with ``json.loads``. The score is ``report["score"]["ppm"]``, an integer
    in parts per million where 1000000 is clean.

    Raises:
        ValueError: when ``text`` is longer than 4 MiB (4194304 bytes of UTF-8); the message
            contains "too large".
        UnicodeEncodeError: when ``text`` contains a lone surrogate.
    """

def score_ppm(text: str) -> int:
    """Return the document score as an integer in parts per million (1000000 is clean).

    This is the ``score.ppm`` of the report ``validate`` returns for the same text.

    Raises:
        ValueError: when ``text`` is longer than 4 MiB (4194304 bytes of UTF-8), exactly as
            ``validate`` does.
    """

def clusters(text: str) -> list[str]:
    """Return the UAX #29 extended grapheme clusters of ``text``, in order, as a list of ``str``.

    The Unicode 15.1 conjunct rule applies, so ``"क्ष"`` is one cluster.

    Raises:
        ValueError: when ``text`` is longer than 4 MiB (4194304 bytes of UTF-8), with the same
            "too large" message as ``validate``.
    """

GATE_SPEC: str
"""The spec string every gate result carries: ``"glyphsift.gate/0.1"``."""

DEFAULT_GATE_THRESHOLD_PPM: int
"""The threshold ``gate`` uses when none is given: 975000 (derived in docs/gate.md)."""

def gate(text: str, threshold_ppm: int | None = None) -> str:
    """Judge one chunk of text and return the canonical JSON gate result (``glyphsift.gate/0.1``).

    The verdict is ``"pass"``, ``"hold"`` (a Devanagari chunk scoring below the threshold) or
    ``"not_scored"`` (text that is not mostly Devanagari is passed through unjudged, with ``ppm`` null).
    Parse the result with ``json.loads``. ``threshold_ppm`` is an ``int`` from 0 to 1000000; ``None``
    means ``DEFAULT_GATE_THRESHOLD_PPM``.

    Raises:
        ValueError: when ``text`` is longer than 4 MiB (the message contains "too large"), when
            ``threshold_ppm`` is outside 0..1000000, or (as ``UnicodeEncodeError``) when ``text`` contains
            a lone surrogate.
        TypeError: when ``threshold_ppm`` is not an ``int`` (a ``bool`` or a ``float`` is refused).
    """
