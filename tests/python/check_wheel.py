#!/usr/bin/env python3
"""Static checks on a built glyphsift wheel (D3-04). Run with -I:

    python3 -I tests/python/check_wheel.py <wheel> <version>

Fails (exit 1) unless the wheel is a cp39-abi3 wheel of the given version that carries the type stub,
the py.typed marker and the licence files; has no file over 5 MB, no wheel over 5 MB, no scripts or
entry points, no test data, no model files and no source maps; and whose packaged METADATA (the page
PyPI would show) carries the honest not-published sentence, the release-candidate wording, the
platform tag proven and the Alpha classifier. Prints one line per check.
"""
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

    name = wheel.rsplit("/", 1)[-1]
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
        import os
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

    check(f"Tag: cp39-abi3-{plat}" in wheel_meta, "WHEEL records the same platform tag as the filename")
    check(HONEST in meta, "the packaged METADATA description contains the honest 'Not published yet ...' sentence")
    check("release candidate, not tagged" in meta, "the packaged README says 'release candidate, not tagged'")
    check("Linux and Windows wheels are not built yet" in meta, "the packaged README says Linux and Windows wheels are not built yet")
    check("built only by CI after the owner's push" in meta, "the packaged README says where those wheels and the sdist come from (built only by CI after the owner's push)")
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
