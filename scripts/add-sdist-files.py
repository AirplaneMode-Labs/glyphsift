#!/usr/bin/env python3
"""Add the four repository-root files the glyphsift-core tests read to a maturin sdist (BUG-T2-S5-12, S1-118).

    python3 -I scripts/add-sdist-files.py <sdist.tar.gz>

maturin cannot include a path outside the Python project (`include` patterns may not contain `..`), and the sdist ships
crates/glyphsift-core/tests, whose gate tests read bench/corpus/clean.txt, docs/gate.md and docs/score-vs-noise.csv
relative to the repository root. Without them 3 of the 14 gate tests fail from the unpacked sdist. Since S1-118 the sdist
test also runs `--features corrupt`, which switches on tests/corrupt.rs; its docs-versus-code test reads
docs/corruption-generator.md, so that file is shipped too (the other shipped test file that needs the feature,
tests/gate_noise.rs, reads only the three above). The CLI crate, and so its own corrupt test, is not in the sdist: maturin
ships only glyphsift-core and glyphsift-py, which is the stated reason that test is absent. This script appends
exactly those four files, at the same relative paths under the sdist's top-level directory, with fixed metadata
(mode 0644, mtime 0, owner root), and rewrites the sdist in place with a gzip header without a timestamp. All three are
synthetic and own-authored. Exit 0 on success, 1 on anything unexpected (a file missing, already present in the sdist,
more than one top-level directory), with the sdist left untouched.
"""
import gzip
import io
import os
import sys
import tarfile

FILES = ["bench/corpus/clean.txt", "docs/gate.md", "docs/score-vs-noise.csv", "docs/corruption-generator.md"]


def main(argv):
    if len(argv) != 2:
        print("usage: add-sdist-files.py <sdist.tar.gz>", file=sys.stderr)
        return 2
    path = argv[1]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with tarfile.open(path, "r:gz") as tar:
        members = tar.getmembers()
        data = {m.name: (tar.extractfile(m).read() if m.isfile() else None) for m in members}
        tar_format = tar.format
    tops = {m.name.split("/", 1)[0] for m in members}
    if len(tops) != 1:
        print(f"error: {path} has more than one top-level directory: {sorted(tops)}", file=sys.stderr)
        return 1
    top = tops.pop()
    extra = []
    for rel in FILES:
        name = f"{top}/{rel}"
        if name in data:
            print(f"error: {name} is already in the sdist", file=sys.stderr)
            return 1
        src = os.path.join(root, *rel.split("/"))
        if not os.path.isfile(src):
            print(f"error: {src} not found", file=sys.stderr)
            return 1
        with open(src, "rb") as f:
            extra.append((name, f.read()))
    raw = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode="w", format=tar_format) as out:
            for m in members:
                if m.isfile():
                    out.addfile(m, io.BytesIO(data[m.name]))
                else:
                    out.addfile(m)
            for name, body in extra:
                info = tarfile.TarInfo(name)
                info.size = len(body)
                info.mode = 0o644
                info.mtime = 0
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                out.addfile(info, io.BytesIO(body))
    tmp = f"{path}.tmp"
    with open(tmp, "wb") as f:
        f.write(raw.getvalue())
    os.replace(tmp, path)
    print(f"added {len(extra)} files to {path}: {', '.join(FILES)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
