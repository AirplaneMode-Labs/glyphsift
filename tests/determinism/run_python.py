#!/usr/bin/env python3
"""Run the determinism samples through the Python binding and require byte-identical output.

Every sample in tests/determinism/samples must produce, through glyphsift.validate(), exactly the
bytes the native CLI printed for it (tests/determinism/expected). Needs the wheel installed
(scripts/determinism.sh runs `maturin develop`). Run with `-I`.
"""
import json
import pathlib
import sys

import glyphsift

# Windows consoles default to cp1252, which cannot print Devanagari. `python -I` ignores
# PYTHONUTF8, so set UTF-8 here.
sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

BASE = pathlib.Path(__file__).resolve().parent
SAMPLES = sorted((BASE / "samples").glob("*.txt"))
MAX_INPUT_BYTES = 4 * 1024 * 1024


def main() -> int:
    if len(SAMPLES) < 8:
        print(f"expected at least 8 samples, found {len(SAMPLES)}", file=sys.stderr)
        return 1
    bad = 0
    for path in SAMPLES:
        # Plain "utf-8": a BOM at offset 0 stays in the text, as it does for the CLI.
        text = path.read_bytes().decode("utf-8")
        want = (BASE / "expected" / f"{path.stem}.json").read_bytes().decode("utf-8")
        got = glyphsift.validate(text) + "\n"
        score = glyphsift.score_ppm(text)
        ok = got == want and score == json.loads(want)["score"]["ppm"]
        print(f"{'ok  ' if ok else 'FAIL'} {path.stem}: python validate() {'equals' if ok else 'DIFFERS FROM'} the native CLI report ({len(got.encode())} bytes, score {score})")
        bad += 0 if ok else 1

    # Input over the core limit is refused with a Python exception, not a crash.
    try:
        glyphsift.validate("क" * (MAX_INPUT_BYTES // 3 + 1))
    except ValueError as err:
        refused = "too large" in str(err)
    else:
        refused = False
    print(f"{'ok  ' if refused else 'FAIL'} input over 4 MiB raises ValueError('... too large ...')")
    bad += 0 if refused else 1

    clusters = glyphsift.clusters("नमस्ते।")
    ok = clusters == ["न", "म", "स्ते", "।"]
    print(f"{'ok  ' if ok else 'FAIL'} clusters('नमस्ते।') == ['न', 'म', 'स्ते', '।']")
    bad += 0 if ok else 1

    # clusters() shares the limit: exactly 4 MiB is accepted, one byte more raises the same ValueError
    # as validate() (BUG-T2-S2-12).
    at_limit = glyphsift.clusters("a" * MAX_INPUT_BYTES)
    ok = len(at_limit) == MAX_INPUT_BYTES
    print(f"{'ok  ' if ok else 'FAIL'} clusters() accepts exactly 4 MiB")
    bad += 0 if ok else 1
    over = "a" * (MAX_INPUT_BYTES + 1)
    try:
        glyphsift.validate(over)
    except ValueError as err:
        want_msg = str(err)
    else:
        want_msg = None
    try:
        glyphsift.clusters(over)
    except ValueError as err:
        ok = want_msg is not None and str(err) == want_msg and "too large" in want_msg
    else:
        ok = False
    print(f"{'ok  ' if ok else 'FAIL'} test_clusters_over_limit_raises_valueerror: clusters() over 4 MiB raises the same ValueError as validate()")
    bad += 0 if ok else 1

    print("python: all samples byte-identical to native" if bad == 0 else f"python: {bad} check(s) failed")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
