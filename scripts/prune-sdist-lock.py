#!/usr/bin/env python3
"""Prune the Cargo.lock inside a maturin sdist to the packages the sdist's own workspace needs (S1-103).

    python3 -I scripts/prune-sdist-lock.py <sdist.tar.gz>

`maturin sdist -m crates/glyphsift-py/Cargo.toml` writes a workspace manifest whose members are only the crates
the Python package needs (glyphsift-core and glyphsift-py) and copies the repository's Cargo.lock unchanged, which
also lists glyphsift-cli, glyphsift-wasm and everything only they use. `cargo build --locked` on the unpacked sdist
then stops with "cannot update the lock file". This script removes from the sdist's Cargo.lock every package that
no workspace member of the sdist reaches, and changes nothing else: no version, no checksum, no dependency list.

The lock is read with tomllib, the reachable set is the closure of the members' dependency lists (a dependency is
"name", "name version" or "name version (source)"), and the file is rewritten as the original text with the
unreached [[package]] blocks cut out, so every kept block is byte-identical. The sdist is rewritten in place with
the same members in the same order, mode, mtime and owner, and a gzip header without a timestamp. Exit 0 when the
lock is pruned or was already minimal, 1 on anything unexpected (a table other than [[package]] in the lock, a
member that is not in the lock, a dependency that cannot be found), with the sdist left untouched.
"""
import gzip
import io
import os
import re
import sys
import tarfile
import tomllib


def fail(message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return 1


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: prune-sdist-lock.py <sdist.tar.gz>", file=sys.stderr)
        return 2
    path = argv[1]
    with tarfile.open(path, "r:gz") as tar:
        members = tar.getmembers()
        data = {m.name: (tar.extractfile(m).read() if m.isfile() else None) for m in members}
        tar_format = tar.format
    tops = {m.name.split("/", 1)[0] for m in members}
    if len(tops) != 1:
        return fail(f"{path} has more than one top-level directory: {sorted(tops)}")
    top = tops.pop()
    lock_name, manifest_name = f"{top}/Cargo.lock", f"{top}/Cargo.toml"
    if data.get(lock_name) is None or data.get(manifest_name) is None:
        return fail(f"{path} has no {lock_name} or no {manifest_name}")

    lock_text = data[lock_name].decode("utf-8")
    manifest = tomllib.loads(data[manifest_name].decode("utf-8"))
    member_dirs = manifest.get("workspace", {}).get("members", [])
    if not member_dirs:
        return fail("the sdist's Cargo.toml has no [workspace] members")
    member_names = []
    for d in member_dirs:
        raw = data.get(f"{top}/{d}/Cargo.toml")
        if raw is None:
            return fail(f"workspace member {d} has no Cargo.toml in the sdist")
        member_names.append(tomllib.loads(raw.decode("utf-8"))["package"]["name"])

    # The lock as text: a header (version = N), then one block per [[package]], nothing else.
    chunks = re.split(r"(?m)^(?=\[\[package\]\]$)", lock_text)
    header, blocks = chunks[0], chunks[1:]
    other = [l for l in lock_text.splitlines() if l.startswith("[") and l != "[[package]]"]
    if other:
        return fail(f"the lock has tables other than [[package]]: {other[:3]}")
    packages = [tomllib.loads(b)["package"][0] for b in blocks]

    def find(dep: str) -> int:
        parts = dep.split(" ", 2)
        name = parts[0]
        version = parts[1] if len(parts) > 1 else None
        source = parts[2].strip("()") if len(parts) > 2 else None
        hits = [
            i
            for i, p in enumerate(packages)
            if p["name"] == name
            and (version is None or p["version"] == version)
            and (source is None or p.get("source") == source)
        ]
        if len(hits) != 1:
            raise LookupError(f"dependency {dep!r} matches {len(hits)} lock entries")
        return hits[0]

    roots = [i for i, p in enumerate(packages) if p["name"] in member_names and "source" not in p]
    if sorted(packages[i]["name"] for i in roots) != sorted(member_names):
        return fail(f"workspace members {member_names} are not all path packages of the lock")
    reached: set[int] = set()
    stack = list(roots)
    try:
        while stack:
            i = stack.pop()
            if i in reached:
                continue
            reached.add(i)
            stack.extend(find(dep) for dep in packages[i].get("dependencies", []))
    except LookupError as e:
        return fail(str(e))

    dropped = [packages[i]["name"] for i in range(len(packages)) if i not in reached]
    kept_blocks = [b for i, b in enumerate(blocks) if i in reached]
    print(f"{path}: lock has {len(packages)} packages, {len(reached)} reachable from {', '.join(member_names)}")
    if not dropped:
        print("nothing to prune: the lock is already minimal")
        return 0
    print(f"dropping {len(dropped)}: {', '.join(sorted(dropped))}")
    new_lock = (header + "".join(kept_blocks)).rstrip("\n") + "\n"

    # Rewrite the sdist: same members, same order, same metadata; only Cargo.lock's bytes differ.
    raw = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode="w", format=tar_format) as out:
            for m in members:
                if m.name == lock_name:
                    body = new_lock.encode("utf-8")
                    info = tarfile.TarInfo(m.name)
                    info.size = len(body)
                    for attr in ("mode", "mtime", "uid", "gid", "uname", "gname", "type"):
                        setattr(info, attr, getattr(m, attr))
                    out.addfile(info, io.BytesIO(body))
                elif m.isfile():
                    out.addfile(m, io.BytesIO(data[m.name]))
                else:
                    out.addfile(m)
    tmp = f"{path}.tmp"
    with open(tmp, "wb") as f:
        f.write(raw.getvalue())
    os.replace(tmp, path)
    print(f"pruned: {lock_name} now has {len(reached)} packages")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
