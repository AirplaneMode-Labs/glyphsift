#!/usr/bin/env python3
"""Static checks on a built glyphsift wheel (D3-04). Run with -I:

    python3 -I tests/python/check_wheel.py <wheel> <version>

Fails (exit 1) unless the wheel is a cp39-abi3 wheel of the given version that carries the type stub,
the py.typed marker and the licence files; has no file over 5 MB, no wheel over 5 MB, no scripts or
entry points, no test data, no model files and no source maps; whose WHEEL file lists exactly the tags the
filename names (PEP 425 compressed tag sets expanded, then compared as sets: see expand_tags); and whose
packaged METADATA (the page PyPI would show) carries the honest not-published sentence, the
release-candidate wording, the platform tag proven and the Alpha classifier. Prints one line per check.

The tests for the tag comparison are tests/python/test_check_wheel.py.
"""
import os
import re
import sys
import zipfile

HONEST = (
    "Not published yet: the npm scope @airplanemode and the PyPI and crates.io names are not reserved. "
    "The commands below were proven from locally built artifacts on macOS arm64 (an npm pack tarball "
    "installed offline into a fresh empty directory, a wheel installed into a fresh venv); publishing "
    "to the registries is the owner's step."
)
MAX_FILE = 5 * 1024 * 1024
# One alternative of one part of a tag (PEP 425): letters, digits and underscores, never empty, no dot.
TAG_ALT = re.compile(r"[A-Za-z0-9_]+")


def expand_tags(compressed: str) -> frozenset:
    """Expand a PEP 425 compressed tag set into the set of python-abi-platform triples it stands for.

    A wheel filename carries `<python>-<abi>-<platform>` where each part may hold several dot-separated
    alternatives, and the tag set is the cross product of the three parts: the manylinux wheel CI builds is
    named `...-cp39-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64.whl` and stands for two tags. Raises
    ValueError for anything that is not three non-empty dash-separated parts of [A-Za-z0-9_] alternatives.
    """
    parts = compressed.split("-")
    if len(parts) != 3:
        raise ValueError(f"{compressed!r} is not <python>-<abi>-<platform> (want 3 dash-separated parts, got {len(parts)})")
    alts = []
    for part in parts:
        a = part.split(".")
        if not all(TAG_ALT.fullmatch(x) for x in a):
            raise ValueError(f"{part!r} in {compressed!r} is not a dot-separated list of non-empty [A-Za-z0-9_] tags")
        alts.append(a)
    return frozenset(f"{py}-{abi}-{plat}" for py in alts[0] for abi in alts[1] for plat in alts[2])


def wheel_file_tags(wheel_meta: str) -> frozenset:
    """The expanded tag set a WHEEL file records: every header named exactly `Tag` (maturin writes one per
    expanded tag), expanded like a filename tag. Other headers, and text that merely contains `Tag:`, are not tags."""
    tags = set()
    for line in re.split(r"\r?\n", wheel_meta):
        key, sep, value = line.partition(":")
        if sep and key == "Tag":
            tags |= expand_tags(value.strip())
    return frozenset(tags)


def tag_mismatch(filename_tags: str, wheel_meta: str):
    """None when the WHEEL file records exactly the tags the filename names (compared as expanded sets, so the
    order of the Tag lines and of the dot-separated alternatives does not matter and nothing may be missing
    or extra); otherwise a one-line description of the difference, or of what could not be parsed."""
    try:
        want = expand_tags(filename_tags)
        have = wheel_file_tags(wheel_meta)
    except ValueError as e:
        return str(e)
    if want == have:
        return None
    said = []
    if want - have:
        said.append("in the filename but not in WHEEL: " + ", ".join(sorted(want - have)))
    if have - want:
        said.append("in WHEEL but not in the filename: " + ", ".join(sorted(have - want)))
    return "; ".join(said)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: check_wheel.py <wheel> <version>", file=sys.stderr)
        return 2
    wheel, version = argv[1], argv[2]
    failures = 0

    def check(ok: bool, what: str) -> None:
        nonlocal failures
        print(("ok   " if ok else "FAIL ") + what)
        if not ok:
            failures += 1

    name = os.path.basename(wheel)
    m = re.fullmatch(r"glyphsift-(?P<v>[^-]+)-cp39-abi3-(?P<plat>[A-Za-z0-9_.]+)\.whl", name)
    check(m is not None and m.group("v") == version, f"wheel name is glyphsift-{version}-cp39-abi3-<platform>.whl (got {name})")
    plat = m.group("plat") if m else "?"
    print(f"     platform tag: {plat}")

    with zipfile.ZipFile(wheel) as z:
        infos = z.infolist()
        names = [i.filename for i in infos]
        di = f"glyphsift-{version}.dist-info/"
        check(any(n.endswith("glyphsift.pyi") or n.endswith("__init__.pyi") for n in names), "the type stub (glyphsift.pyi) is in the wheel")
        check(any(n.endswith("/py.typed") for n in names), "py.typed is in the wheel")
        check(di + "licenses/LICENSE" in names, "LICENSE is in the wheel")
        check(di + "licenses/NOTICE" in names, "NOTICE is in the wheel")
        if di + "licenses/NOTICE" in names:
            nt = z.read(di + "licenses/NOTICE").decode("utf-8")
            check("Permission is hereby granted" in nt, "the wheel NOTICE carries the MIT text (TD-28)")
            check("zmij 1.0.23" in nt and "David Tolnay" in nt, "the wheel NOTICE carries the zmij block")
            check("memchr 2.8.3" in nt and "Andrew Gallant" in nt, "the wheel NOTICE carries the memchr block")
            check("does not bundle those texts" not in nt, "the wheel NOTICE no longer says the texts are not bundled")
        check(any(n.endswith(".abi3.so") or n.endswith(".pyd") for n in names), "the compiled extension is in the wheel")
        big = [(i.filename, i.file_size) for i in infos if i.file_size > MAX_FILE]
        check(not big, f"no file over 5 MB {big if big else ''}")
        size = os.path.getsize(wheel)
        check(size < MAX_FILE, f"the wheel is under 5 MB ({size} bytes)")
        bad = [n for n in names if re.search(r"(\.map$|\.onnx$|\.safetensors$|\.gguf$|(^|/)tests?/|\.data/scripts/|entry_points\.txt$|\.pth$)", n)]
        check(not bad, f"no source maps, model files, tests, scripts or entry points {bad if bad else ''}")
        unexpected = [
            n for n in names
            if not (n.startswith("glyphsift/") or n.startswith(di))
        ]
        check(not unexpected, f"every file is under glyphsift/ or the dist-info {unexpected if unexpected else ''}")
        meta = z.read(di + "METADATA").decode("utf-8")
        wheel_meta = z.read(di + "WHEEL").decode("utf-8")

    # PEP 425/427: the filename carries a compressed tag set and WHEEL one Tag line per expanded tag, so the two
    # are compared as expanded sets (CI run 44325740893: a plain string compare failed the manylinux wheel only).
    mismatch = tag_mismatch(f"cp39-abi3-{plat}", wheel_meta) if m else "the filename did not parse, so its tags are unknown"
    check(mismatch is None, "WHEEL records the same tag set as the filename (compressed tags expanded, compared as sets)")
    if mismatch is not None:
        print(f"     {mismatch}")
    else:
        print(f"     tags: {', '.join(sorted(wheel_file_tags(wheel_meta)))}")
    check(HONEST in meta, "the packaged METADATA description contains the honest 'Not published yet ...' sentence")
    check("release candidate, not tagged" in meta, "the packaged README says 'release candidate, not tagged'")
    # Sprint 5 (D3-03): CI built the Linux and Windows wheels and an sdist at 5ff0c47 (run 43667702791, read on
    # 18 Nov 2026); they are workflow artifacts, not releases, and nothing is published.
    check("Linux and Windows wheels were built by CI" in meta, "the packaged README says CI built the Linux and Windows wheels")
    check("43667702791" in meta, "the packaged README cites the CI run that built them (43667702791)")
    check("nothing from that job is published" in meta, "the packaged README says nothing from that job is published")
    check("built only by CI after the owner's push" not in meta and "Linux and Windows wheels are not built yet" not in meta, "the packaged README no longer says the Linux and Windows wheels are unbuilt")
    check("glyphsift.gate(" in meta, "the packaged README documents glyphsift.gate()")
    # The README records the tag that was installed and proven (macOS arm64); a wheel built elsewhere (CI on
    # Linux) has another tag, and the README must not claim that one was proven.
    check("macosx_11_0_arm64" in meta, "the packaged README records the platform tag proven (macosx_11_0_arm64)")
    if plat != "macosx_11_0_arm64":
        print(f"     note: this wheel's tag is {plat}; the README still says only macosx_11_0_arm64 was proven")
    check("After the owner publishes" in meta, "the packaged README has an 'After the owner publishes' block")
    check("Classifier: Development Status :: 3 - Alpha" in meta, "classifier is 'Development Status :: 3 - Alpha'")
    check("Pre-Alpha" not in meta, "no Pre-Alpha classifier remains")
    check("Classifier: Operating System :: MacOS" in meta and "OS Independent" not in meta, "OS classifier is 'MacOS' (no Linux or Windows wheel exists yet), not 'OS Independent'")
    check("Classifier: Typing :: Typed" in meta, "classifier 'Typing :: Typed' is present")
    # A bare registry command may appear only after the 'After the owner publishes' heading.
    head, _, tail = meta.partition("After the owner publishes")
    check(not re.search(r"pip install glyphsift|cargo install glyphsift-cli|npm i(nstall)? @airplanemode", head), "no bare registry command before the 'After the owner publishes' block")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
