"""Fail if any file inside a wheel (.whl, zip), an npm tarball (.tgz), or a plain file (a binary) contains a builder path.

    python3 -I scripts/check-no-builder-paths.py <artifact> [<artifact> ...]

Searched as bytes in every member: b"/Users/", b"/home/", b"/private/tmp" (and the Windows form
b"C:\\\\Users\\\\" ). Exit 0 when clean, 1 with the member and offset of each hit.
"""
import sys
import tarfile
import zipfile

NEEDLES = [b"/Users/", b"/home/", b"/private/tmp", b"C:\\Users\\", b"C:/Users/"]


def members(path):
    if path.endswith(".whl") or path.endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            for n in z.namelist():
                yield n, z.read(n)
    elif path.endswith((".tgz", ".tar", ".tar.gz")):
        with tarfile.open(path, "r:*") as t:
            for m in t.getmembers():
                if m.isfile():
                    yield m.name, t.extractfile(m).read()
    else:  # a plain file, such as the installed CLI binary
        with open(path, "rb") as f:
            yield path, f.read()


def main(argv):
    if not argv:
        print("usage: check-no-builder-paths.py <artifact>...", file=sys.stderr)
        return 2
    bad = 0
    for art in argv:
        n_files = 0
        for name, data in members(art):
            n_files += 1
            for needle in NEEDLES:
                i = data.find(needle)
                if i != -1:
                    ctx = data[max(0, i - 20): i + 60]
                    print(f"FAIL {art}: {name} offset {i} contains {needle!r}: {ctx!r}", file=sys.stderr)
                    bad += 1
        print(f"checked {n_files} files in {art}")
    if bad:
        return 1
    print("ok: no builder path in any packed file")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
