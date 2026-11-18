// Tests for scripts/lib/confine.mjs: the --out containment of scripts/release-manifest.mjs.
//
//   node --test tests/scripts/confine.test.mjs        (run by tests/scripts/run-all.sh and by the `check` job on every OS)
//
// Ported from AirplaneMode-Labs/pagetriage tests/scripts/confine.test.mjs (Sprint 5, Part A, TD-45; extended to
// glyphsift by TD-53, fix round 1, after the security review found the same containment fault here: T2 reproduced
// on macOS a hard-link overwrite outside dist/, a write through a symlink to a file inside dist/, a false refusal of
// a differently-cased dist/ and two stack traces). The two copies of the library are the same file apart from the
// header that names its source; the cases below are pagetriage's plus the hard-link cases, which only glyphsift
// carries. If you change one copy, change the other and say so in the CHANGELOG.
//
// Why a model of Windows at all: the Mac that develops this repository cannot run Windows. So the Windows path rules
// are tested here with node:path's win32 flavour and an in-memory file system that behaves like a Windows volume
// (case-insensitive names, 8.3 short names, symlinks and junctions, a reparse point that lstat does not report). The
// same confinement code then runs unchanged on every OS. The last sections use the real file system, real symlinks,
// real hard links and, on Windows only, a real junction.
//
// CONFINE_LIB overrides the module under test (an absolute file path). It exists so the suite can be run
// against the pre-fix code for the red log; leave it unset otherwise.
//
// Nothing here is ever skipped. A case that does not apply to this OS prints "not applicable on <os>"; a link
// that cannot be created fails the test.
import { test } from "node:test";
import assert from "node:assert/strict";
import nodeFs from "node:fs";
import { spawnSync } from "node:child_process";
import nodeOs from "node:os";
import nodePath from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = nodePath.dirname(fileURLToPath(import.meta.url));
const LIB = process.env.CONFINE_LIB || nodePath.join(HERE, "..", "..", "scripts", "lib", "confine.mjs");
const lib = await import(pathToFileURL(LIB).href);
const { confineOutput, Refusal } = lib;

// ---------------------------------------------------------------------------------------------------------
// An in-memory volume. It is only as faithful as the behaviours the confinement code can depend on:
//   - name lookup is case-insensitive when `ci` (Windows) and the on-disk spelling wins in realpath.native;
//   - `aliases` map an 8.3 short name to the long name of the same entry (RUNNER~1 -> runneradmin);
//   - the extended-length prefix \\?\ and \\.\ and the \\localhost\C$\ admin share name the same file;
//   - lstat does not follow the last component; every other component is followed;
//   - a `hidden` junction is a reparse point that lstat reports as a plain directory (as for a volume mount
//     point or another reparse tag) while path resolution still follows it;
//   - realpathSync (the JS implementation) keeps the spelling of every component that lstat says is not a
//     link, as Node's does; realpathSync.native returns the canonical on-disk path.
// ---------------------------------------------------------------------------------------------------------
function fsError(code, p) {
  const e = new Error(`${code}: ${p}`);
  e.code = code;
  return e;
}

class FakeFs {
  constructor({ pathMod, ci, aliases = [] }) {
    this.p = pathMod;
    this.ci = ci;
    this.alias = new Map(aliases.map(([short, long]) => [short.toLowerCase(), long]));
    this.roots = new Map();
    this.realpathSync = Object.assign((p) => this.#jsRealpath(p), { native: (p) => this.#walk(p, true).canon });
  }

  #key(name) { return this.ci ? name.toLowerCase() : name; }

  // Strip the spellings that Windows treats as the same path, then normalise separators.
  #prep(p) {
    let s = String(p);
    if (this.p === nodePath.win32) {
      s = s.replace(/\//g, "\\");
      s = s.replace(/^\\\\[?.]\\(?=[A-Za-z]:)/, "");
      s = s.replace(/^\\\\localhost\\([A-Za-z])\$\\/i, "$1:\\");
    }
    return this.p.normalize(s);
  }

  #rootNode(root, create) {
    const k = this.#key(root);
    let n = this.roots.get(k);
    if (!n && create) {
      n = { name: root, type: "dir", children: new Map() };
      this.roots.set(k, n);
    }
    return n;
  }

  // Create `p` (and any missing parents as plain directories). Used to build fixtures.
  add(p, type = "dir", extra = {}) {
    const n = this.#prep(p);
    const root = this.p.parse(n).root;
    let node = this.#rootNode(root, true);
    const comps = n.slice(root.length).split(this.p.sep).filter(Boolean);
    comps.forEach((comp, i) => {
      const k = this.#key(comp);
      let child = node.children.get(k);
      const last = i === comps.length - 1;
      if (!child) {
        child = { name: comp, type: last ? type : "dir", children: new Map(), ...(last ? extra : {}) };
        node.children.set(k, child);
      }
      node = child;
    });
    return this;
  }

  #walk(p, followFinal, hops = { n: 0 }) {
    const n = this.#prep(p);
    const root = this.p.parse(n).root;
    const rootNode = this.#rootNode(root, false);
    if (!rootNode) throw fsError("ENOENT", p);
    let node = rootNode;
    let canon = this.p === nodePath.win32 ? root.toUpperCase() : root;
    const queue = n.slice(root.length).split(this.p.sep).filter((c) => c && c !== ".");
    while (queue.length) {
      const raw = queue.shift();
      const comp = this.alias.get(raw.toLowerCase()) ?? raw;
      if (node.type !== "dir") throw fsError("ENOTDIR", p);
      const child = node.children.get(this.#key(comp));
      if (!child) throw fsError("ENOENT", p);
      const last = queue.length === 0;
      if ((child.type === "symlink" || child.type === "junction") && (!last || followFinal)) {
        if (++hops.n > 32) throw fsError("ELOOP", p);
        const target = this.p.resolve(canon, child.target);
        const rest = queue.join(this.p.sep);
        return this.#walk(rest ? this.p.join(target, rest) : target, followFinal, hops);
      }
      canon = this.p.join(canon, child.name);
      node = child;
    }
    return { canon, node };
  }

  #stats(node) {
    const link = (node.type === "symlink" || node.type === "junction") && !node.hidden;
    return {
      isSymbolicLink: () => link,
      isDirectory: () => node.type === "dir" || (node.type === "junction" && !!node.hidden),
      isFile: () => node.type === "file",
    };
  }

  lstatSync(p) { return this.#stats(this.#walk(p, false).node); }
  readlinkSync(p) {
    const { node } = this.#walk(p, false);
    if (!node.target) throw fsError("EINVAL", p);
    return node.target;
  }

  #jsRealpath(p) {
    const n = this.#prep(p);
    const root = this.p.parse(n).root;
    const queue = n.slice(root.length).split(this.p.sep).filter((c) => c && c !== ".");
    let base = root;
    while (queue.length) {
      base = this.p.join(base, queue.shift());
      if (this.lstatSync(base).isSymbolicLink()) {
        const target = this.p.resolve(this.p.dirname(base), this.readlinkSync(base));
        return this.realpathSync(queue.length ? this.p.join(target, ...queue) : target);
      }
    }
    this.lstatSync(base); // must exist
    return base;
  }

  mkdirSync(p, opts = {}) {
    try {
      const { node } = this.#walk(p, true);
      if (node.type !== "dir") throw fsError("EEXIST", p);
      return;
    } catch (e) {
      if (e.code !== "ENOENT") throw e;
    }
    if (!opts.recursive) throw fsError("ENOENT", p);
    const parent = this.p.dirname(this.#prep(p));
    this.mkdirSync(parent, opts);
    const { node: pn, canon } = this.#walk(parent, true);
    if (pn.type !== "dir") throw fsError("ENOTDIR", p);
    const name = this.p.basename(this.#prep(p));
    pn.children.set(this.#key(name), { name, type: "dir", children: new Map() });
    void canon;
  }
}

function winVolume() {
  const R = "C:\\Users\\runneradmin\\w\\repo";
  const O = "C:\\Users\\runneradmin\\w\\outside";
  const v = new FakeFs({ pathMod: nodePath.win32, ci: true, aliases: [["RUNNER~1", "runneradmin"]] });
  v.add(`${R}\\dist\\sub`).add(`${R}\\dist\\real.json`, "file").add(`${R}\\art`).add(`${O}\\target.json`, "file")
    .add(`${R}\\dist\\dirlink`, "symlink", { target: O })
    .add(`${R}\\dist\\filelink.json`, "symlink", { target: `${O}\\target.json` })
    .add(`${R}\\dist\\inner.json`, "symlink", { target: `${R}\\dist\\real.json` })
    .add(`${R}\\dist\\junc`, "junction", { target: O })
    .add(`${R}\\dist\\hidden`, "junction", { target: O, hidden: true })
    .add(`${R}\\dist\\dangling`, "symlink", { target: "C:\\nowhere\\at\\all" })
    .add("D:\\other");
  return { fs: v, pathMod: nodePath.win32, platform: "win32", root: R, outside: O };
}

function posixVolume() {
  const R = "/work/repo";
  const O = "/work/outside";
  const v = new FakeFs({ pathMod: nodePath.posix, ci: false });
  v.add(`${R}/dist/sub`).add(`${R}/dist/real.json`, "file").add(`${O}/target.json`, "file")
    .add(`${R}/dist/dirlink`, "symlink", { target: O })
    .add(`${R}/dist/filelink.json`, "symlink", { target: `${O}/target.json` })
    .add(`${R}/dist/inner.json`, "symlink", { target: `${R}/dist/real.json` })
    .add(`${R}/dist/dangling`, "symlink", { target: "/nowhere/at/all" })
    .add("/private/var/repo2/dist").add("/var", "symlink", { target: "/private/var" });
  return { fs: v, pathMod: nodePath.posix, platform: "darwin", root: R, outside: O };
}

function attempt(env, out, root) {
  try {
    const plan = confineOutput(out, { root: root ?? env.root, pathMod: env.pathMod, fs: env.fs, platform: env.platform });
    return { ok: true, plan };
  } catch (e) {
    if (e instanceof Refusal) return { ok: false, msg: e.message };
    throw e;
  }
}
function accepted(env, out, expectTarget, root) {
  const r = attempt(env, out, root);
  assert.ok(r.ok, `expected ${JSON.stringify(out)} to be accepted, was refused: ${r.msg}`);
  if (expectTarget !== undefined) assert.equal(r.plan.target, expectTarget, `target for ${JSON.stringify(out)}`);
}
function refused(env, out, reason, root) {
  const r = attempt(env, out, root);
  assert.ok(!r.ok, `expected ${JSON.stringify(out)} to be refused, was accepted as ${r.plan && r.plan.target}`);
  assert.match(r.msg, reason, `refusal reason for ${JSON.stringify(out)}`);
}

const INSIDE = /must resolve inside dist\//;
const DOTDOT = /must not contain '\.\.'/;
const LINK = /symbolic link or junction/;

// ---------------------------------------------------------------------------------------------------------
// Windows model (path.win32 + the volume above)
// ---------------------------------------------------------------------------------------------------------
const WR = "C:\\Users\\runneradmin\\w\\repo";

test("win32: plain relative and absolute paths inside dist/ are accepted, in every separator spelling", () => {
  const w = winVolume();
  accepted(w, "dist\\x.json", `${WR}\\dist\\x.json`);
  accepted(w, "dist/sub/x.json", `${WR}\\dist\\sub\\x.json`);
  accepted(w, "dist/sub\\x.json", `${WR}\\dist\\sub\\x.json`);
  accepted(w, `${WR}\\dist\\x.json`, `${WR}\\dist\\x.json`);
  accepted(w, "C:/Users/runneradmin/w/repo/dist\\sub/x.json", `${WR}\\dist\\sub\\x.json`);
  accepted(w, "dist\\a\\b\\c.json", `${WR}\\dist\\a\\b\\c.json`);
  accepted(w, "dist\\.\\x.json", `${WR}\\dist\\x.json`); // a single-dot component is not a trailing-dot name
  accepted(w, "dist\\..foo.json", `${WR}\\dist\\..foo.json`); // starts with two dots but is not '..'
  accepted(w, "dist\\real.json", `${WR}\\dist\\real.json`); // overwriting a regular file is allowed
});

test("win32 spelling: drive-letter case is not a difference (mechanism candidate 1 for run 43667700010)", () => {
  const w = winVolume();
  accepted(w, `c:\\Users\\runneradmin\\w\\repo\\dist\\x.json`, `${WR}\\dist\\x.json`);
  accepted(w, `C:\\USERS\\RunnerAdmin\\W\\REPO\\DIST\\x.json`, `${WR}\\dist\\x.json`);
});

test("win32 spelling: an 8.3 short name and the long name of the same directory are the same place (candidate 2)", () => {
  const w = winVolume();
  accepted(w, "C:\\Users\\RUNNER~1\\w\\repo\\dist\\x.json", `${WR}\\dist\\x.json`);
  // the other way round: the script was found through the short name, the caller typed the long one
  accepted(w, `${WR}\\dist\\x.json`, `${WR}\\dist\\x.json`, "C:\\Users\\RUNNER~1\\w\\repo");
  accepted(w, "dist\\x.json", `${WR}\\dist\\x.json`, "C:\\Users\\RUNNER~1\\w\\repo");
});

test("win32 containment: '..', other directories, another drive and dist/ itself are refused", () => {
  const w = winVolume();
  refused(w, "..\\x.json", DOTDOT);
  refused(w, "dist\\..\\x.json", DOTDOT);
  refused(w, "dist/../x.json", DOTDOT);
  refused(w, "out.json", INSIDE);
  refused(w, `${w.outside}\\x.json`, INSIDE);
  refused(w, "D:\\other\\x.json", INSIDE);
  refused(w, "dist", /inside dist\/|is a directory/);
  refused(w, "dist\\", /inside dist\/|is a directory/);
  refused(w, `${WR}\\dist`, /inside dist\/|is a directory/);
});

test("win32 rule 1: extended-length and device prefixes (\\\\?\\ and \\\\.\\) are refused by name", () => {
  const w = winVolume();
  const re = /extended-length or device path/;
  refused(w, `\\\\?\\${WR}\\dist\\x.json`, re);
  refused(w, `\\\\.\\${WR}\\dist\\x.json`, re);
  refused(w, `//?/${WR.replace(/\\/g, "/")}/dist/x.json`, re);
  refused(w, "\\\\?\\GLOBALROOT\\Device\\HarddiskVolume1\\x.json", re);
});

test("win32 rule 2: UNC paths are refused by name, including the admin share of this very drive", () => {
  const w = winVolume();
  const re = /UNC path/;
  refused(w, "\\\\server\\share\\x.json", re);
  refused(w, "//server/share/x.json", re);
  refused(w, `\\\\localhost\\C$\\Users\\runneradmin\\w\\repo\\dist\\x.json`, re);
});

test("win32 rule 3: drive-relative paths are refused by name (their meaning depends on a per-drive cwd)", () => {
  const w = winVolume();
  const re = /drive-relative/;
  refused(w, "C:x.json", re);
  refused(w, "C:dist\\x.json", re);
  refused(w, "D:x.json", re);
  refused(w, "C:", re);
  refused(w, "c:dist/x.json", re);
});

test("win32 rule 4: a ':' after the drive (alternate data stream) is refused by name", () => {
  const w = winVolume();
  const re = /alternate data stream/;
  refused(w, "dist\\x.json:evil", re);
  refused(w, "dist\\x.json::$DATA", re);
  refused(w, "dist:evil\\x.json", re);
  refused(w, `${WR}\\dist\\x.json:s`, re);
  refused(w, "dist\\sub\\:x", re);
});

test("win32 rule 5: reserved device names are refused by name, with or without an extension, in any case", () => {
  const w = winVolume();
  const re = /reserved device name/;
  for (const out of ["dist\\NUL", "dist\\con", "dist\\COM1.json", "dist\\lpt9.tar.gz", "dist\\sub\\AuX.txt",
    "dist\\PRN.", "dist\\NUL .txt", "dist\\CONIN$", "dist\\conout$.log", "dist\\COM\u00b9", "dist\\LPT\u00b2.txt", "NUL", "COM5\\x.json"]) {
    // 'dist\\PRN.' also ends in a dot; either named rule is a refusal by name
    refused(w, out, /reserved device name|end in '\.' or ' '/);
  }
  refused(w, "dist\\NUL", re);
  // names that merely start with a reserved word are fine
  accepted(w, "dist\\console.json", `${WR}\\dist\\console.json`);
  accepted(w, "dist\\com10.json", `${WR}\\dist\\com10.json`);
  accepted(w, "dist\\nullable.json", `${WR}\\dist\\nullable.json`);
  accepted(w, "dist\\auxiliary", `${WR}\\dist\\auxiliary`);
});

test("win32 rule 6: a component ending in '.' or ' ' is refused by name (Windows would strip it)", () => {
  const w = winVolume();
  const re = /end in '\.' or ' '/;
  refused(w, "dist\\x.json.", re);
  refused(w, "dist\\x.json ", re);
  refused(w, "dist\\sub.\\x.json", re);
  refused(w, "dist\\x.json. .", re);
  refused(w, "dist\\ \\x.json", re);
});

test("win32: characters Windows does not allow in a file name are refused by name", () => {
  const w = winVolume();
  const re = /character Windows does not allow/;
  for (const out of ["dist\\a<b.json", "dist\\a>b", "dist\\a|b", "dist\\a?b", "dist\\a*b", 'dist\\a"b', "dist\\a\u0001b"]) refused(w, out, re);
});

test("win32 symlinks: a directory symlink or junction on the way that leaves dist/ is refused", () => {
  const w = winVolume();
  refused(w, "dist\\dirlink\\x.json", INSIDE);
  refused(w, "dist\\junc\\x.json", INSIDE);
  refused(w, `${WR}\\dist\\dirlink\\sub\\x.json`, INSIDE);
});

test("win32 junction modelled by a fake realpath: a reparse point that lstat reports as a directory is still followed", () => {
  const w = winVolume();
  // lstat says 'directory', so a check that only asks lstat sees a plain folder; realpath.native resolves it.
  assert.equal(w.fs.lstatSync(`${WR}\\dist\\hidden`).isSymbolicLink(), false);
  assert.equal(w.fs.realpathSync.native(`${WR}\\dist\\hidden`), w.outside);
  refused(w, "dist\\hidden\\x.json", INSIDE);
  refused(w, "dist\\hidden\\sub\\deeper\\x.json", INSIDE);
  refused(w, "dist\\hidden", /directory|inside dist\//);
});

test("win32 final component: an existing symlink or junction is refused, whatever it points at", () => {
  const w = winVolume();
  refused(w, "dist\\filelink.json", LINK); // points outside dist/
  refused(w, "dist\\inner.json", LINK); // points at a file inside dist/: still never written through
  refused(w, "dist\\junc", LINK);
  refused(w, "dist\\dirlink", LINK);
  refused(w, "dist\\dangling", /dangling|symbolic link or junction/);
  refused(w, `${WR}\\dist\\inner.json`, LINK);
});

test("win32: a dangling symlink in the middle of the path is refused", () => {
  const w = winVolume();
  refused(w, "dist\\dangling\\x.json", /dangling symlink/);
});

test("win32: an existing directory as --out is a refusal, not a crash later", () => {
  const w = winVolume();
  refused(w, "dist\\sub", /is a directory/);
});

test("win32: NUL and empty --out are refusals", () => {
  const w = winVolume();
  refused(w, "dist\\x\u0000.json", /NUL/);
  const r = attempt(w, "");
  assert.equal(r.ok, false);
});

test("win32 rules do not depend on the platform string being 'linux' or 'darwin' elsewhere: the same inputs pass on posix", () => {
  const p = posixVolume();
  accepted(p, "dist/CON", "/work/repo/dist/CON");
  accepted(p, "dist/x.json:evil", "/work/repo/dist/x.json:evil");
  accepted(p, "dist/x.json.", "/work/repo/dist/x.json.");
  accepted(p, "dist/a<b|c", "/work/repo/dist/a<b|c");
  accepted(p, "dist/NUL .txt", "/work/repo/dist/NUL .txt");
});

// ---------------------------------------------------------------------------------------------------------
// POSIX model (path.posix + a case-sensitive volume)
// ---------------------------------------------------------------------------------------------------------
test("posix: relative and absolute paths inside dist/ are accepted; case matters", () => {
  const p = posixVolume();
  accepted(p, "dist/x.json", "/work/repo/dist/x.json");
  accepted(p, "/work/repo/dist/sub/x.json", "/work/repo/dist/sub/x.json");
  accepted(p, "dist/..foo.json", "/work/repo/dist/..foo.json");
  accepted(p, "dist/real.json", "/work/repo/dist/real.json");
  refused(p, "Dist/x.json", INSIDE);
});

test("posix: '..' in either separator spelling, other directories and dist/ itself are refused", () => {
  const p = posixVolume();
  refused(p, "../x.json", DOTDOT);
  refused(p, "dist/../x.json", DOTDOT);
  refused(p, "dist\\..\\x.json", DOTDOT);
  refused(p, "out.json", INSIDE);
  refused(p, "/work/outside/x.json", INSIDE);
  refused(p, "dist", /inside dist\/|is a directory/);
  refused(p, "dist/sub/..", DOTDOT);
});

test("posix: symlinks leaving dist/, final symlinks (any target), dangling links and directories are refused", () => {
  const p = posixVolume();
  refused(p, "dist/dirlink/x.json", INSIDE);
  refused(p, "dist/filelink.json", LINK);
  refused(p, "dist/inner.json", LINK);
  refused(p, "dist/dangling/x.json", /dangling symlink/);
  refused(p, "dist/dangling", /dangling|symbolic link or junction/);
  refused(p, "dist/sub", /is a directory/);
});

test("posix: a root reached through a symlink (macOS /var -> /private/var) is compared after realpath on both sides", () => {
  const p = posixVolume();
  accepted(p, "dist/x.json", undefined, "/var/repo2");
  accepted(p, "/private/var/repo2/dist/x.json", undefined, "/var/repo2");
  accepted(p, "/var/repo2/dist/x.json", undefined, "/var/repo2");
  refused(p, "/private/var/other/x.json", INSIDE, "/var/repo2");
});

// ---------------------------------------------------------------------------------------------------------
// The real file system, real links
// ---------------------------------------------------------------------------------------------------------
function realTree(t) {
  const base = nodeFs.realpathSync(nodeFs.mkdtempSync(nodePath.join(nodeOs.tmpdir(), "confine-")));
  t.after(() => nodeFs.rmSync(base, { recursive: true, force: true }));
  const root = nodePath.join(base, "repo");
  const outside = nodePath.join(base, "outside");
  nodeFs.mkdirSync(nodePath.join(root, "dist", "sub"), { recursive: true });
  nodeFs.mkdirSync(outside, { recursive: true });
  nodeFs.writeFileSync(nodePath.join(outside, "target.json"), "");
  nodeFs.writeFileSync(nodePath.join(root, "dist", "real.json"), "{}\n");
  return { base, root, outside };
}
function mustLink(target, link, type) {
  try {
    nodeFs.symlinkSync(target, link, type);
  } catch (e) {
    assert.fail(`could not create a symlink: containment unproven on this runner (${e.code} ${link})`);
  }
  assert.ok(nodeFs.lstatSync(link).isSymbolicLink(), `${link} is not a link after creating it`);
}
function realAttempt(root, out) {
  try {
    return { ok: true, plan: confineOutput(out, { root }) };
  } catch (e) {
    if (e instanceof Refusal) return { ok: false, msg: e.message };
    throw e;
  }
}
const dirLinkType = process.platform === "win32" ? "junction" : "dir"; // a junction needs no privilege on Windows

test("real fs: a relative path inside dist/ is accepted and a new nested directory is allowed", (t) => {
  const { root } = realTree(t);
  assert.equal(realAttempt(root, "dist/x.json").ok, true);
  assert.equal(realAttempt(root, "dist/a/b/c.json").ok, true);
  assert.equal(realAttempt(root, nodePath.join(root, "dist", "abs.json")).ok, true);
});

test("real fs: a directory link leaving dist/ is refused, and nothing is created behind it", (t) => {
  const { root, outside } = realTree(t);
  mustLink(outside, nodePath.join(root, "dist", "link"), dirLinkType);
  const r = realAttempt(root, "dist/link/x.json");
  assert.equal(r.ok, false);
  assert.match(r.msg, INSIDE);
  assert.equal(nodeFs.existsSync(nodePath.join(outside, "x.json")), false);
});

test("real fs: a file link at the final component is refused whether it points outside or inside dist/", (t) => {
  const { root, outside } = realTree(t);
  mustLink(nodePath.join(outside, "target.json"), nodePath.join(root, "dist", "filelink.json"), "file");
  mustLink(nodePath.join(root, "dist", "real.json"), nodePath.join(root, "dist", "inner.json"), "file");
  for (const name of ["filelink.json", "inner.json"]) {
    const r = realAttempt(root, `dist/${name}`);
    assert.equal(r.ok, false, name);
    assert.match(r.msg, LINK, name);
  }
  assert.equal(nodeFs.statSync(nodePath.join(outside, "target.json")).size, 0);
});

test("real fs: a dangling link on the way is refused", (t) => {
  const { root, base } = realTree(t);
  mustLink(nodePath.join(base, "no-such-place"), nodePath.join(root, "dist", "dangling"), dirLinkType === "junction" ? "file" : "dir");
  const r = realAttempt(root, "dist/dangling/x.json");
  assert.equal(r.ok, false);
});

test("real fs: a directory as --out is refused", (t) => {
  const { root } = realTree(t);
  const r = realAttempt(root, "dist/sub");
  assert.equal(r.ok, false);
  assert.match(r.msg, /is a directory/);
});

test("real fs: a regular file at dist/ is a one-line Refusal, not a stack trace (BUG-T2-S5-03)", (t) => {
  const { root } = realTree(t);
  nodeFs.rmSync(nodePath.join(root, "dist"), { recursive: true });
  nodeFs.writeFileSync(nodePath.join(root, "dist"), "not a directory");
  const r = realAttempt(root, "dist/m.json");
  assert.equal(r.ok, false);
  assert.match(r.msg, /dist\/ .*(not a directory|cannot be created)/);
  assert.ok(!r.msg.includes("\n"), "one line");
});

test("real fs: a dangling symlink at dist/ is a one-line Refusal, not a stack trace (BUG-T2-S5-03)", (t) => {
  const { root, base } = realTree(t);
  nodeFs.rmSync(nodePath.join(root, "dist"), { recursive: true });
  mustLink(nodePath.join(base, "no-such-place"), nodePath.join(root, "dist"), dirLinkType === "junction" ? "file" : "dir");
  const r = realAttempt(root, "dist/m.json");
  assert.equal(r.ok, false);
  assert.match(r.msg, /dist\/ .*(not a directory|cannot be created|dangling)/);
  assert.ok(!r.msg.includes("\n"), "one line");
});

test("real fs: an existing --out that is a FIFO is refused as not a regular file (BUG-T2-S5-04)", (t) => {
  if (process.platform === "win32") {
    console.log("# FIFO case: not applicable on win32");
    t.diagnostic("FIFO case: not applicable on win32");
    return;
  }
  const { root } = realTree(t);
  const fifo = nodePath.join(root, "dist", "pipe.json");
  const mk = spawnSync("mkfifo", [fifo]);
  assert.equal(mk.status, 0, "mkfifo must work on this runner: " + String(mk.stderr));
  assert.ok(nodeFs.lstatSync(fifo).isFIFO(), "a FIFO exists");
  const r = realAttempt(root, "dist/pipe.json");
  assert.equal(r.ok, false);
  assert.match(r.msg, /not a regular file/);
});

test("real fs: a junction leaving dist/ is refused (Windows only; elsewhere: not applicable)", (t) => {
  if (process.platform !== "win32") {
    console.log(`# junction case: not applicable on ${process.platform}`);
    t.diagnostic(`junction case: not applicable on ${process.platform}`);
    return;
  }
  const { root, outside } = realTree(t);
  try {
    nodeFs.symlinkSync(outside, nodePath.join(root, "dist", "junc"), "junction");
  } catch (e) {
    assert.fail(`could not create a junction: containment unproven on this runner (${e.code})`);
  }
  assert.ok(nodeFs.lstatSync(nodePath.join(root, "dist", "junc")).isSymbolicLink(), "node reports a junction as a link");
  const r = realAttempt(root, "dist/junc/x.json");
  assert.equal(r.ok, false);
  assert.match(r.msg, INSIDE);
  const f = realAttempt(root, "dist/junc");
  assert.equal(f.ok, false);
});

// ---------------------------------------------------------------------------------------------------------
// Hard links (glyphsift only: T2's adv-real run R34 overwrote a file outside dist/ through a hard link)
// ---------------------------------------------------------------------------------------------------------
function mustHardLink(existing, link) {
  try {
    nodeFs.linkSync(existing, link);
  } catch (e) {
    assert.fail(`could not create a hard link: containment unproven on this runner (${e.code} ${link})`);
  }
  assert.ok(nodeFs.statSync(link).nlink >= 2, `${link} has one name only after linking it`);
}

// ---------------------------------------------------------------------------------------------------------
// writeConfined: temporary name opened with 'wx' inside the realpath'd parent, then rename
// ---------------------------------------------------------------------------------------------------------
const writeConfined = lib.writeConfined;

test("writeConfined: writes the bytes, replaces an existing regular file, and leaves no temporary file", (t) => {
  const { root } = realTree(t);
  assert.equal(typeof writeConfined, "function", "writeConfined is exported");
  const plan = confineOutput("dist/sub/m.json", { root });
  writeConfined(plan, "one\n");
  assert.equal(nodeFs.readFileSync(nodePath.join(root, "dist", "sub", "m.json"), "utf8"), "one\n");
  writeConfined(confineOutput("dist/sub/m.json", { root }), "two\n");
  assert.equal(nodeFs.readFileSync(nodePath.join(root, "dist", "sub", "m.json"), "utf8"), "two\n");
  assert.deepEqual(nodeFs.readdirSync(nodePath.join(root, "dist", "sub")), ["m.json"]);
  writeConfined(confineOutput("dist/new/deeper/n.json", { root }), "x");
  assert.equal(nodeFs.readFileSync(nodePath.join(root, "dist", "new", "deeper", "n.json"), "utf8"), "x");
});

test("writeConfined: re-checks the parent just before writing, so a directory swapped for a link after the check is refused", (t) => {
  const { root, outside } = realTree(t);
  assert.equal(typeof writeConfined, "function", "writeConfined is exported");
  const plan = confineOutput("dist/sub/m.json", { root });
  nodeFs.rmSync(nodePath.join(root, "dist", "sub"), { recursive: true });
  mustLink(outside, nodePath.join(root, "dist", "sub"), dirLinkType);
  assert.throws(() => writeConfined(plan, "x"), (e) => e instanceof Refusal && INSIDE.test(e.message));
  assert.deepEqual(nodeFs.readdirSync(outside), ["target.json"], "nothing was written outside dist/");
});

test("writeConfined: a temporary name that already exists is never overwritten", (t) => {
  const { root } = realTree(t);
  assert.equal(typeof writeConfined, "function", "writeConfined is exported");
  const plan = confineOutput("dist/m.json", { root });
  const taken = nodePath.join(root, "dist", ".release-manifest-fixed.tmp");
  nodeFs.writeFileSync(taken, "keep me");
  const suffixes = ["fixed", "fixed", "other"];
  writeConfined(plan, "data", { randomSuffix: () => suffixes.shift() });
  assert.equal(nodeFs.readFileSync(taken, "utf8"), "keep me");
  assert.equal(nodeFs.readFileSync(nodePath.join(root, "dist", "m.json"), "utf8"), "data");
  assert.equal(nodeFs.existsSync(nodePath.join(root, "dist", ".release-manifest-other.tmp")), false, "temporary file renamed away");
});

test("hard link: a name in dist/ that is a second name of a file outside dist/ is replaced, and the outside file keeps its bytes", (t) => {
  const { root, outside } = realTree(t);
  const other = nodePath.join(outside, "keep.json");
  nodeFs.writeFileSync(other, "ORIGINAL");
  const inDist = nodePath.join(root, "dist", "hard.json");
  mustHardLink(other, inDist);
  // lstat calls a hard link a regular file, so the plan is accepted; what matters is how the bytes are written.
  const plan = confineOutput("dist/hard.json", { root });
  writeConfined(plan, "NEW\n");
  assert.equal(nodeFs.readFileSync(other, "utf8"), "ORIGINAL", "the outside file was not written through the hard link");
  assert.equal(nodeFs.readFileSync(inDist, "utf8"), "NEW\n", "dist/hard.json now holds the manifest");
  assert.equal(nodeFs.statSync(inDist).nlink, 1, "dist/hard.json is a new file, no longer a second name of the outside file");
  assert.deepEqual(nodeFs.readdirSync(nodePath.join(root, "dist")).filter((n) => n.endsWith(".tmp")), [], "no temporary file left");
});

test("hard link: two names inside dist/ are both left alone when a third name is written (rename replaces one name only)", (t) => {
  const { root } = realTree(t);
  const a = nodePath.join(root, "dist", "real.json");
  const b = nodePath.join(root, "dist", "second-name.json");
  mustHardLink(a, b);
  writeConfined(confineOutput("dist/second-name.json", { root }), "NEW\n");
  assert.equal(nodeFs.readFileSync(a, "utf8"), "{}\n", "the other name of the same file keeps its bytes");
  assert.equal(nodeFs.readFileSync(b, "utf8"), "NEW\n");
});
