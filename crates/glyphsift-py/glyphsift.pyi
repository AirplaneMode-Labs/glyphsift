"""Type stubs for the glyphsift Python wheel (release candidate 0.1.0, not tagged).

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
