#!/usr/bin/env python3
"""Sprint 7, fix round 1 (BUG-T3-S7-07, S1-130, S1-131, TD-125): tests/scripts/ci-policy.sh is only worth its green if it goes RED when a workflow or release-script rule is
broken. This driver copies the workflows and the release scripts to a scratch directory, breaks one rule at a time (a mutation), runs ci-policy.sh against the copy
(WF=<scratch workflows> RELD=<scratch scripts>) and expects it to fail; a control run on the unmutated copy must pass. A mutation the policy does not catch is a hole
in the policy. Run it through tests/scripts/ci-policy-mutations.sh (which tests/scripts/run-all.sh picks up); nothing here touches the real files or the network.

    python3 -I tests/scripts/ci-policy-mutations.py <repository root>
"""
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(sys.argv[1]).resolve()
POLICY = REPO / "tests" / "scripts" / "ci-policy.sh"
PASSES = 0
FAILS = 0


def ok(msg):
    global PASSES
    PASSES += 1
    print("ok   - " + msg)


def fail(msg):
    global FAILS
    FAILS += 1
    print("FAIL - " + msg)


def fresh(tmp):
    for d in ("wf", "rel"):
        shutil.rmtree(tmp / d, ignore_errors=True)
        (tmp / d).mkdir()
    for f in (REPO / ".github" / "workflows").glob("*.yml"):
        shutil.copy(f, tmp / "wf" / f.name)
    for f in (REPO / "scripts" / "release").glob("*.sh"):
        shutil.copy(f, tmp / "rel" / f.name)


def policy(tmp):
    env = dict(os.environ, WF=str(tmp / "wf"), RELD=str(tmp / "rel"), CI_POLICY_NO_CARGO_DOC="1")
    r = subprocess.run(["bash", str(POLICY)], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    first = next((l for l in r.stdout.splitlines() if l.startswith("FAIL")), "")
    return r.returncode, first


# ---- mutation helpers: each returns a function from the file text to the mutated text ---------------------------------------
def sub(old, new, count=1):
    def f(s):
        if old not in s:
            raise LookupError("anchor not found: " + repr(old[:90]))
        return s.replace(old, new, count)
    return f


def in_job(job, inner):
    """Apply `inner` to the text of one job of a workflow (the lines between `  <job>:` and the next two-space job key)."""
    def f(s):
        m = re.search(r"^  " + re.escape(job) + r":[ \t]*\n", s, re.M)
        if not m:
            raise LookupError("no job " + job)
        n = re.search(r"^  [A-Za-z0-9_-]+:[ \t]*\n", s[m.end():], re.M)
        end = m.end() + (n.start() if n else len(s) - m.end())
        return s[:m.end()] + inner(s[m.end():end]) + s[end:]
    return f


def move_block(start_marker, before_marker):
    """Cut the text from start_marker to the end of the file and paste it just before before_marker."""
    def f(s):
        i = s.index(start_marker)
        block, rest = s[i:], s[:i]
        j = rest.index(before_marker)
        return rest[:j] + block + rest[j:]
    return f


def move_between(start_marker, end_marker, before_marker):
    """Cut the text from start_marker up to end_marker and paste it just before before_marker (which comes later in the file)."""
    def f(s):
        i, j = s.index(start_marker), s.index(end_marker)
        block = s[i:j]
        rest = s[:i] + s[j:]
        k = rest.index(before_marker)
        return rest[:k] + block + rest[k:]
    return f


def append(text):
    return lambda s: s.rstrip("\n") + "\n" + text


P, C = "publish.yml", "ci.yml"
ARMED_IF = "    if: github.repository == 'AirplaneMode-Labs/glyphsift' && github.ref == 'refs/heads/main'\n    runs-on: ubuntu-latest\n"
BUILD_IF = "    if: github.repository == 'AirplaneMode-Labs/glyphsift' && github.ref == 'refs/heads/main'\n    runs-on: ${{ matrix.os }}\n"
NPM_LINE = 'npm publish "./verified/$(cat lists/npm.txt)"'
MUTATIONS = [
    # ---- publish.yml: triggers, permissions, locks --------------------------------------------------------------------------
    ("publish: a push trigger", "wf", P, sub("on:\n  workflow_dispatch:\n", "on:\n  push:\n    branches: [main]\n  workflow_dispatch:\n")),
    ("publish: a pull_request trigger", "wf", P, sub("on:\n  workflow_dispatch:\n", "on:\n  pull_request:\n  workflow_dispatch:\n")),
    ("publish: a pull_request_target trigger", "wf", P, sub("on:\n  workflow_dispatch:\n", "on:\n  pull_request_target:\n  workflow_dispatch:\n")),
    ("publish: a workflow_dispatch input", "wf", P, sub("  workflow_dispatch:\n", "  workflow_dispatch:\n    inputs:\n      go:\n        type: string\n")),
    ("publish: top-level permissions left writable", "wf", P, sub("permissions: {}\n", "permissions:\n  contents: write\n")),
    ("publish: the release environment removed", "wf", P, sub("    environment: release\n", "")),
    ("publish: the repository and main guard removed from the build job", "wf", P, sub(BUILD_IF, "    runs-on: ${{ matrix.os }}\n")),
    ("publish: id-token in the build job", "wf", P, sub("    timeout-minutes: 75\n    permissions:\n      contents: read\n", "    timeout-minutes: 75\n    permissions:\n      contents: read\n      id-token: write\n")),
    ("publish: attestations missing from the publish job", "wf", P, sub("      attestations: write\n", "")),
    ("publish: a third job", "wf", P, append("  extra:\n    runs-on: ubuntu-latest\n    permissions:\n      contents: read\n    steps:\n      - run: true\n")),
    # TD-125
    ("TD-125: vars.RELEASE_PUBLISH_ARMED in a job-level if", "wf", P, sub(ARMED_IF, ARMED_IF.replace("refs/heads/main'\n", "refs/heads/main' && vars.RELEASE_PUBLISH_ARMED == 'true'\n"))),
    ("TD-125: a step before the armed check", "wf", P, sub("      - name: Lock 3, RELEASE_PUBLISH_ARMED is true\n", "      - run: echo before the armed check\n      - name: Lock 3, RELEASE_PUBLISH_ARMED is true\n")),
    ("TD-125: the armed check removed", "wf", P, sub("run: scripts/release/publish-guard.sh armed", "run: 'true'")),
    ("TD-125: the armed variable read at job level", "wf", P, sub("    timeout-minutes: 30\n", "    timeout-minutes: 30\n    env:\n      ARMED: ${{ vars.RELEASE_PUBLISH_ARMED }}\n")),
    ("TD-125: the key id read at job level", "wf", P, sub("    timeout-minutes: 30\n", "    timeout-minutes: 30\n    env:\n      KEYID: ${{ vars.RELEASE_KEY_ID }}\n")),
    ("TD-125: the third-party rust-toolchain action moved before lock 6", "wf", P, move_between("      # the one third-party action before the publishing steps", "      - name: Read the version from the package file", "      # lock 6: the key id")),
    ("lock 6 (the key id check) removed", "wf", P, sub("run: scripts/release/publish-guard.sh key-id", "run: 'true'")),
    ("the registry-absent check removed", "wf", P, sub('run: GUARD_VERSION="$VERSION" scripts/release/publish-guard.sh registry-absent', "run: 'true'")),
    ("the tag binding removed", "wf", P, sub('run: GUARD_VERSION="$VERSION" scripts/release/publish-guard.sh tag-binding', "run: 'true'")),
    ("verification without --expect-id", "wf", P, sub(" --expect-id glyphsift-release --trust-file docs/release-keys.json", " --trust-file docs/release-keys.json")),
    ("verification with the test key", "wf", P, sub("--trust-file docs/release-keys.json", "--trust-test-key --allow-test-key")),
    # ---- publish.yml: provenance and the publish steps ------------------------------------------------------------------------
    ("provenance moved after the PyPI action", "wf", P, lambda s: (lambda a: s.replace(a, "") + a)(s[s.index("      # provenance: after every check"):s.index("      # S1-130:")])),
    ("npm publish without --provenance", "wf", P, sub(" --provenance", "")),
    ("npm publish without --ignore-scripts", "wf", P, sub(" --ignore-scripts --tag", " --tag")),
    ("PyPI without attestations: true", "wf", P, sub("          attestations: true\n", "")),
    ("a PyPI token", "wf", P, sub("          attestations: true\n", "          attestations: true\n          password: ${{ secrets.PYPI_TOKEN }}\n")),
    ("another secret instead of NPM_TOKEN", "wf", P, sub("secrets.NPM_TOKEN", "secrets.GITHUB_TOKEN")),
    ("a token in a run step", "wf", P, sub("        run: cargo publish --workspace --locked --no-verify", "        run: CARGO_REGISTRY_TOKEN=${{ secrets.CARGO_REGISTRY_TOKEN }} cargo publish --workspace --locked --no-verify")),
    ("download from another run (run-id)", "wf", P, sub("          merge-multiple: true\n", "          merge-multiple: true\n          run-id: 123\n")),
    ("a cache input in the build job", "wf", P, sub('          python-version: "3.12"\n', '          python-version: "3.12"\n          cache: pip\n')),
    ("candidate retention of 14 days", "wf", P, sub("          retention-days: 1\n", "          retention-days: 14\n")),
    ("upload without if-no-files-found: error", "wf", P, sub("          if-no-files-found: error\n", "")),
    ("a checkout that keeps credentials", "wf", P, sub("          persist-credentials: false\n", "")),
    ("an action by tag instead of SHA", "wf", P, sub("actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1", "actions/checkout@v4")),
    ("an action SHA that is not in the table", "wf", P, sub("pypa/gh-action-pypi-publish@7245906fb61fa33a13554f9d5fb856fe61758086", "pypa/gh-action-pypi-publish@0000000000000000000000000000000000000000")),
    # ---- BUG-T3-S7-01 / S1-130: the npm argument -------------------------------------------------------------------------------------
    ("S1-130: npm publish of a bare verified/<file> path (a GitHub shorthand to npm)", "wf", P, sub(NPM_LINE, 'npm publish "verified/$(cat lists/npm.txt)"')),
    ("S1-130: npm publish of a glob", "wf", P, sub(NPM_LINE, "npm publish ./verified/*.tgz")),
    ("S1-130: npm publish with no path (the working directory)", "wf", P, sub(NPM_LINE + " --provenance", "npm publish --provenance")),
    ("S1-130: the dry run reverts to an absolute native path", "rel", "publish-dry-run.sh", sub('&& npm publish "./verified/$(cat lists/npm.txt)"', '&& npm publish "$(to_native "$TGZ")"')),
    ("S1-130: the dry run uses a bare verified/ path", "rel", "publish-dry-run.sh", sub('&& npm publish "./verified/$(cat lists/npm.txt)"', '&& npm publish "verified/$(cat lists/npm.txt)"')),
    ("S1-130: the dry run no longer builds the workflow's layout", "rel", "publish-dry-run.sh", sub('cp "$TGZ" "$LAYOUT/verified/"\n', "")),
    # ---- BUG-T3-S7-07: run: blocks, timeouts, installs, packages-dir ------------------------------------------------------------------
    ("run: VERSION from ${{ github.ref_name }}", "wf", P, sub("VERSION=$(scripts/release/publish-guard.sh version)", "VERSION=${{ github.ref_name }}")),
    ("run: GUARD_VERSION from ${{ github.sha }}", "wf", P, sub('run: GUARD_VERSION="$VERSION" scripts/release/publish-guard.sh registry-absent', 'run: GUARD_VERSION="${{ github.sha }}" scripts/release/publish-guard.sh registry-absent')),
    ("run: SOURCE_DATE_EPOCH from ${{ github.run_id }}", "wf", P, sub("SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)", "SOURCE_DATE_EPOCH=${{ github.run_id }}")),
    ("PyPI packages-dir is verified/", "wf", P, sub("          packages-dir: pypi-dist/\n", "          packages-dir: verified/\n")),
    ("PyPI packages-dir is another directory", "wf", P, sub("          packages-dir: pypi-dist/\n", "          packages-dir: dist/\n")),
    ("PyPI staging makes the directory with mkdir -p", "wf", P, sub("          mkdir pypi-dist\n", "          mkdir -p pypi-dist\n")),
    ("PyPI staging no longer checks the count", "wf", P, sub("          test \"$(ls -A pypi-dist | wc -l | tr -d ' ')\" = \"$(wc -l < lists/pypi.txt | tr -d ' ')\"\n", "")),
    ("a step between the PyPI staging step and the PyPI action", "wf", P, sub("      - uses: pypa/gh-action-pypi-publish@", "      - run: echo between\n      - uses: pypa/gh-action-pypi-publish@")),
    ("no timeout on the build job", "wf", P, sub("    timeout-minutes: 75\n", "")),
    ("no timeout on the publish job", "wf", P, sub("    timeout-minutes: 30\n", "")),
    ("release-rehearsal installs the CLI from the checkout (cargo install --path)", "wf", C, in_job("release-rehearsal", sub("      - name: Rehearsal (build, clean-machine install checks", "      - run: cargo install --path crates/glyphsift-cli --locked\n      - name: Rehearsal (build, clean-machine install checks"))),
    ("release-rehearsal installs the wheel from the checkout (pip install .)", "wf", C, in_job("release-rehearsal", sub("      - name: Rehearsal (build, clean-machine install checks", "      - run: python -m pip install ./crates/glyphsift-py\n      - name: Rehearsal (build, clean-machine install checks"))),
    ("release-rehearsal runs maturin develop", "wf", C, in_job("release-rehearsal", sub("      - name: Rehearsal (build, clean-machine install checks", "      - run: maturin develop\n      - name: Rehearsal (build, clean-machine install checks"))),
    ("publish: a cargo install in the publish job", "wf", P, sub("      - name: Re-package the crates", "      - run: cargo install --path crates/glyphsift-cli\n      - name: Re-package the crates")),
    ("deny: the matrix value interpolated into the run step again", "wf", C, in_job("deny", sub('--all-features check $CHECKS', "--all-features check ${{ matrix.checks }}"))),
    ("deny: CHECKS no longer passed through step env", "wf", C, in_job("deny", sub("          CHECKS: ${{ matrix.checks }}\n", "          CHECKS: advisories\n"))),
    ("deny: CHECKS not validated", "wf", C, in_job("deny", sub('          case "$CHECKS" in\n            advisories|"bans licenses sources") ;;\n            *) echo "unexpected cargo-deny checks: $CHECKS" >&2; exit 1 ;;\n          esac\n', ""))),
    # FR2 BUG-T3-S7-20: continue-on-error, step-level if, and a deny default arm that does not exit
    ("FR2 m9: deny default arm does nothing ('*) ;;')", "wf", C, in_job("deny", sub('*) echo "unexpected cargo-deny checks: $CHECKS" >&2; exit 1 ;;', '*) ;;'))),
    ("FR2: continue-on-error on the verify step", "wf", P, sub("      - name: Lock 4, verify the signed manifest against docs/release-keys.json\n", "      - name: Lock 4, verify the signed manifest against docs/release-keys.json\n        continue-on-error: true\n")),
    ("FR2: continue-on-error on the tag binding", "wf", P, sub("      - name: Binding 1, tag v<version> peels to this commit\n", "      - name: Binding 1, tag v<version> peels to this commit\n        continue-on-error: true\n")),
    ("FR2: if: always() on npm publish", "wf", P, sub("      - name: Publish the npm package (provenance, public, no install scripts, a derived dist-tag)\n", "      - name: Publish the npm package (provenance, public, no install scripts, a derived dist-tag)\n        if: always()\n")),
    ("FR2: if: always() on cargo publish", "wf", P, sub("      - name: Publish the crates (glyphsift-core, then glyphsift-cli; the publish = false crates are skipped; no build in this job)\n", "      - name: Publish the crates (glyphsift-core, then glyphsift-cli; the publish = false crates are skipped; no build in this job)\n        if: always()\n")),
    ("a matrix value interpolated into another run step", "wf", C, in_job("check", sub("      - run: cargo fmt --all --check\n", "      - run: echo ${{ matrix.os }}\n      - run: cargo fmt --all --check\n"))),
    ("vars. in the job-level if of a ci job", "wf", C, in_job("doc", sub("    runs-on: ubuntu-latest\n", "    if: vars.SOMETHING == 'true'\n    runs-on: ubuntu-latest\n"))),
    # ---- BUG-S1-S7-03 / S1-131: the crates ---------------------------------------------------------------------------------------------
    ("S1-131: cargo package without --no-verify", "wf", P, sub("cargo package --workspace --locked --no-verify", "cargo package --workspace --locked")),
    ("S1-131: cargo publish without --no-verify", "wf", P, sub("run: cargo publish --workspace --locked --no-verify", "run: cargo publish --workspace --locked")),
    ("S1-131: a cargo build in the publish job", "wf", P, sub("      - name: Re-package the crates", "      - run: cargo build --locked\n      - name: Re-package the crates")),
    ("S1-131: crates published without the digest comparison", "wf", P, sub('          GUARD_VERSION="$VERSION" scripts/release/publish-guard.sh crate-digests verified target/package\n', "")),
    ("S1-131: a step between the digest comparison and cargo publish", "wf", P, sub("      - name: Publish the crates (glyphsift-core", "      - run: echo between\n      - name: Publish the crates (glyphsift-core")),
    ("S1-131: the crates.io index check removed", "wf", P, sub('        run: GUARD_VERSION="$VERSION" scripts/release/publish-guard.sh crate-index verified', "        run: 'true'")),
    ("S1-131: the crates.io index check given a longer window", "wf", P, sub("publish-guard.sh crate-index verified", "publish-guard.sh crate-index verified 600 15")),
    ("S1-131: the PyPI staging and action moved before the crates", "wf", P, move_block("      - name: Stage exactly the PyPI files", "      # S1-131 (S1-126, TD-123): the crates are re-packaged")),
    ("S1-131: the crates published before npm", "wf", P, move_between("      # S1-130: the argument starts with ./", "      # S1-131 (S1-126, TD-123): the crates are re-packaged", "      - name: Stage exactly the PyPI files")),
    ("S1-131: the dry run drops --no-verify", "rel", "publish-dry-run.sh", sub("cargo publish --dry-run --workspace --locked --no-verify ${DIRTY", "cargo publish --dry-run --workspace --locked ${DIRTY")),
    ("S1-131: build-artefacts no longer packages with --no-verify", "rel", "build-artefacts.sh", sub("for mode in verify noverify; do", "for mode in verify; do")),
    ("S1-131: build-artefacts no longer compares the --no-verify bytes", "rel", "build-artefacts.sh", sub('[ "$A" = "$C" ] && [ "$A" = "$D" ] || die', 'true || die')),
    ("S1-131: crate-index reads over plain http", "rel", "publish-guard.sh", sub('url="https://index.crates.io/', 'url="http://index.crates.io/')),
    ("S1-131: crate-index window raised", "rel", "publish-guard.sh", sub("window=600 interval=15", "window=6000 interval=15")),
    ("S1-131: crate-index no longer compares the cksum", "rel", "publish-guard.sh", sub("h.cksum !== want", "false")),
    # ---- the earlier rules the new ones sit beside ------------------------------------------------------------------------------------
    ("release-rehearsal: Swatinem/rust-cache added", "wf", C, in_job("release-rehearsal", sub("    steps:\n", "    steps:\n      - uses: Swatinem/rust-cache@d1527c8f67ef9af357290475d4af4b0fab8f12e0 # v2.9.3\n"))),
    ("release-rehearsal: artefact kept 14 days", "wf", C, in_job("release-rehearsal", sub("          retention-days: 3\n", "          retention-days: 14\n"))),
    ("release-rehearsal: hidden files included in the upload", "wf", C, in_job("release-rehearsal", sub("          include-hidden-files: false\n", ""))),
    ("release-rehearsal: the build tree added to the upload", "wf", C, in_job("release-rehearsal", sub("            dist-release-report/\n", "            dist-release-report/\n            target/\n"))),
    ("release-rehearsal: the artefact not named as a rehearsal", "wf", C, in_job("release-rehearsal", sub("REHEARSAL-test-key-NOT-A-RELEASE-glyphsift-", "glyphsift-"))),
    ("release-rehearsal: a plain pip install of the tools", "wf", C, in_job("release-rehearsal", sub("-m pip install --require-hashes --no-deps --only-binary=:all: -r tools/ci/requirements.txt", "-m pip install maturin"))),
    ("release-rehearsal: id-token granted", "wf", C, in_job("release-rehearsal", sub("    permissions:\n      contents: read\n", "    permissions:\n      contents: read\n      id-token: write\n"))),
    ("ci: a secret", "wf", C, in_job("release-rehearsal", sub("    env:\n      TOOLS_BIN:", "    env:\n      TOKEN: ${{ secrets.X }}\n      TOOLS_BIN:"))),
    # ---- O: every toolchain step installs what rust-toolchain.toml lists (pagetriage CI run 44651022212) ----------------------------
    ("O: release-rehearsal toolchain step without components", "wf", C, in_job("release-rehearsal", sub("          components: rustfmt, clippy\n", ""))),
    ("O: release-rehearsal toolchain step without the wasm32 target", "wf", C, in_job("release-rehearsal", sub("          targets: wasm32-unknown-unknown\n", ""))),
    ("O: the publish job's toolchain step without components", "wf", P, in_job("publish", sub("          components: rustfmt, clippy\n", ""))),
    ("O: a toolchain step on another channel than rust-toolchain.toml", "wf", P, sub('          toolchain: "1.98"\n', '          toolchain: "1.99"\n')),
    ("O: the Pages toolchain step without components", "wf", "pages.yml", sub("          components: rustfmt, clippy\n", "")),
]


def main():
    global MUTATIONS
    with tempfile.TemporaryDirectory(prefix="ci-policy-mut.") as t:
        tmp = pathlib.Path(t)
        fresh(tmp)
        rc, first = policy(tmp)
        if rc == 0:
            ok("control: the unmutated workflows and scripts pass the policy")
        else:
            fail("control: the unmutated workflows and scripts pass the policy (" + first[:120] + ")")
        for name, where, fname, fn in MUTATIONS:
            fresh(tmp)
            path = tmp / ("wf" if where == "wf" else "rel") / fname
            try:
                text = path.read_text()
                new = fn(text)
            except (LookupError, ValueError) as e:
                fail("mutation '" + name + "' could not be applied: " + str(e))
                continue
            if new == text:
                fail("mutation '" + name + "' changed nothing")
                continue
            path.write_text(new)
            rc, first = policy(tmp)
            if rc == 1:
                ok("red on: " + name + " (" + first.replace("FAIL - ", "")[:100] + ")")
            elif rc == 0:
                fail("the policy stayed green on: " + name)
            else:
                fail("the policy crashed (exit " + str(rc) + ") on: " + name)
    print(str(PASSES) + " passed, " + str(FAILS) + " failed")
    return 0 if FAILS == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
