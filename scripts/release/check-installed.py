#!/usr/bin/env python3
"""One real, asserted call against an INSTALLED glyphsift wheel (Sprint 7, D3-02; the release rehearsal's clean-machine check).

    <venv>/bin/python -I scripts/release/check-installed.py --venv <venv> --tests <tests dir> --version <x.y.z>

The wheel was installed into a fresh virtual environment named .venv (PIP_NO_INDEX=1, pip install --no-index --no-deps). Run it with the
VENV'S OWN python and -I (isolated: neither this script's directory nor the user site is on sys.path), so `import glyphsift` can only come
from the environment's site-packages. Checks: sys.prefix is the venv; the module file is inside the venv's site-packages and the path
contains '.venv'; the version is the expected one; and a clean and a corrupted Devanagari sample are validated and gated to exactly the
bytes committed under tests/determinism (the same two samples as scripts/release/check-installed.mjs). Exit 0 when all checks hold.
Standard library only; no network, no environment variable is read.
"""
import json
import os
import sys
import sysconfig

sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

FAILS = 0


def check(ok, what):
    global FAILS
    print(("ok   " if ok else "FAIL ") + what)
    if not ok:
        FAILS += 1


def opt(name):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else None


def main():
    venv, tests, version = opt("--venv"), opt("--tests"), opt("--version")
    if not (venv and tests and version):
        print("usage: check-installed.py --venv <dir> --tests <dir> --version <x.y.z>", file=sys.stderr)
        return 2
    det = os.path.join(tests, "determinism")
    samples = [("01-clean-hindi", "pass"), ("03-ocr-corrupted", "hold")]
    cases = [json.loads(line) for line in open(os.path.join(det, "gate", "cases.jsonl"), encoding="utf-8") if line.strip()]
    expected = [line for line in open(os.path.join(det, "gate", "expected.jsonl"), encoding="utf-8").read().split("\n") if line]
    fixtures = []
    for name, verdict in samples:
        text = open(os.path.join(det, "samples", name + ".txt"), "rb").read().decode("utf-8")
        report = open(os.path.join(det, "expected", name + ".json"), "rb").read().decode("utf-8")
        idx = next((i for i, c in enumerate(cases) if c["note"] == "determinism sample " + name and c["threshold_ppm"] is None), None)
        gate = expected[idx] if idx is not None else None
        check(gate is not None and cases[idx]["text"] == text, f"fixture {name}: the gate case holds the sample's own text")
        check(gate is not None and json.loads(gate)["verdict"] == verdict, f"fixture {name}: the committed gate bytes say {verdict}")
        fixtures.append((name, verdict, text, report, gate))

    import glyphsift  # only possible from the venv: -I removes the script directory from sys.path

    module = os.path.realpath(glyphsift.__file__)
    venv_real = os.path.realpath(venv)
    print("module: " + module)
    check(os.path.realpath(sys.prefix) == venv_real, "sys.prefix is the fresh venv")
    site_dirs = {os.path.realpath(sysconfig.get_paths()[k]) for k in ("purelib", "platlib")}
    check(any(module.startswith(d + os.sep) for d in site_dirs), "glyphsift.__file__ is inside the venv's site-packages")
    check(module.startswith(venv_real + os.sep), "glyphsift.__file__ is under the venv directory")
    check(".venv" in module, "the module path contains '.venv'")
    for name, verdict, text, report, gate in fixtures:
        check(glyphsift.validate(text) + "\n" == report, f"validate({name}) equals the committed report bytes")
        check(glyphsift.gate(text) == gate, f"gate({name}) equals the committed gate bytes ({verdict})")
    check(json.loads(glyphsift.validate(fixtures[0][2]))["score"]["ppm"] == 1000000, "the clean sample scores 1000000 ppm")
    check(glyphsift.score_ppm(fixtures[1][2]) < 975000, "the corrupted sample scores below the 975000 ppm gate threshold")
    try:
        from importlib.metadata import version as dist_version

        check(dist_version("glyphsift") == version, f"the installed distribution is glyphsift {version}")
    except Exception as e:  # a missing dist-info is a failure, not a skip
        check(False, f"importlib.metadata could not read glyphsift's version: {e}")
    print("installed wheel check: " + ("all checks passed" if FAILS == 0 else f"{FAILS} FAILED"))
    return 0 if FAILS == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
