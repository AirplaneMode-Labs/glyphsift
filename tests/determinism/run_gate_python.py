#!/usr/bin/env python3
"""Python leg of the gate determinism check (Sprint 5, D3-01).

glyphsift.gate() over the 200-case corpus in tests/determinism/gate must return, byte for byte, the line recorded
in expected.jsonl. A case recorded as `rejected` must raise ValueError: an unpaired surrogate (which PyO3 cannot turn
into a Rust &str, UnicodeEncodeError is a ValueError) and input over 4 MiB. Needs the wheel installed
(scripts/determinism.sh runs `maturin develop`). Run with `-I`.
"""
import json
import pathlib
import sys

import glyphsift

sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

GATE = pathlib.Path(__file__).resolve().parent / "gate"


def text_of(case):
    if "parts" in case:
        return "".join(s * k for s, k in case["parts"])
    return case["text"]


def main() -> int:
    cases = [json.loads(l) for l in (GATE / "cases.jsonl").read_text(encoding="utf-8").split("\n") if l]
    expected = [l for l in (GATE / "expected.jsonl").read_text(encoding="utf-8").split("\n") if l]
    bad = 0
    value_errors = 0
    for case, want in zip(cases, expected):
        text = text_of(case)
        threshold = case["threshold_ppm"]
        try:
            got = glyphsift.gate(text) if threshold is None else glyphsift.gate(text, threshold)
        except ValueError:
            got = "rejected"
            value_errors += 1
        if got != want:
            bad += 1
            print(f"FAIL {case['id']} ({case['note']}): got {got[:200]!r}; want {want[:200]!r}")
    ok = bad == 0 and len(cases) == 200 and len(expected) == 200
    print(f"{'ok  ' if ok else 'FAIL'} python gate() matches expected.jsonl on all {len(cases)} cases")
    refused = sum(1 for w in expected if w == "rejected")
    ok2 = value_errors == refused == 7
    print(f"{'ok  ' if ok2 else 'FAIL'} the seven rejected cases raise ValueError ({value_errors} of {refused})")
    # The default threshold and the spec string are exported.
    ok3 = glyphsift.DEFAULT_GATE_THRESHOLD_PPM == 975000 and glyphsift.GATE_SPEC == "glyphsift.gate/0.1"
    print(f"{'ok  ' if ok3 else 'FAIL'} glyphsift.DEFAULT_GATE_THRESHOLD_PPM is 975000 and glyphsift.GATE_SPEC is glyphsift.gate/0.1")
    # A threshold outside 0..1000000 is a ValueError, a bool or a float is a TypeError.
    errs = []
    for bad_threshold, exc in [(1000001, ValueError), (-1, ValueError), (2**40, ValueError), (2**70, ValueError), (1.5, TypeError), ("1", TypeError)]:
        try:
            glyphsift.gate("नमस्ते", bad_threshold)
            errs.append(f"{bad_threshold!r} was accepted")
        except exc:
            pass
        except Exception as e:  # noqa: BLE001
            errs.append(f"{bad_threshold!r} raised {type(e).__name__}, want {exc.__name__}")
    print(f"{'ok  ' if not errs else 'FAIL'} a threshold outside 0..1000000 raises ValueError, a non-integer one TypeError {errs if errs else ''}")
    all_ok = ok and ok2 and ok3 and not errs
    print("gate python: 200 cases match" if all_ok else "gate python: FAILED")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
