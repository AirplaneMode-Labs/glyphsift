// Output-path confinement for scripts/release-manifest.mjs (Sprint 5, Part A; team decisions TD-45 and TD-53).
//
// SOURCE: AirplaneMode-Labs/pagetriage scripts/lib/confine.mjs. This copy is the same file apart from this paragraph:
// glyphsift's own check (a startsWith on realpath, then writeFileSync) refused a differently-cased dist/, accepted a
// symlink to a file inside dist/ and wrote through it, wrote through a hard link to a file outside dist/ and printed a
// stack trace for two ordinary errors (T2, BUG-T2-S5-02). If you change one copy, change the other. The unit tests are
// tests/scripts/confine.test.mjs (the same cases plus the hard-link cases) and tests/scripts/release-manifest.sh.
//
// The manifest may only be written to a regular file inside this repository's dist/ directory, after every
// symbolic link, junction and 8.3 short name on the way has been resolved. This module holds the check and the
// write, takes everything it touches as parameters ({pathMod, fs, platform}) so that the Windows rules can be
// tested on any OS with path.win32 and a fake file system (tests/scripts/confine.test.mjs), and has no
// dependency outside node:.
//
// The checks, in order (docs/release.md, "Output confinement", says the same in prose):
//   1. --out is a non-empty string without a NUL.
//   2. No '..' component in either separator spelling.
//   3. Windows only (platform === 'win32'), on the text as typed: no extended-length or device prefix
//      (\\?\ \\.\), no UNC path, no drive-relative path (C:x), no ':' after the drive (alternate data stream),
//      no reserved device name (CON PRN AUX NUL COM1-9 LPT1-9, any case, with or without an extension), no
//      component ending in '.' or ' ' (Windows strips those, so the name on disk would differ from the name
//      checked), no character Windows does not allow in a file name.
//   4. dist/ and the deepest existing ancestor of --out are resolved with realpathSync.native (on Windows that
//      is GetFinalPathNameByHandle: it expands 8.3 short names, gives names their on-disk case, uppercases the
//      drive letter and follows every junction and symlink, including reparse points that lstat does not
//      report as links). A dangling link on the way is refused.
//   5. If --out itself exists it must be a regular file: a symbolic link or junction (whatever it points at) and
//      a directory are refused.
//   6. Containment is rel = relative(distReal, final): rel must be non-empty, must not be absolute (another
//      drive), and must not be '..' or start with '..' plus a separator. A name that merely starts with two dots
//      ('..foo') is fine. The comparison is case-insensitive only because path.win32.relative is, and only
//      after realpath.native has made both sides canonical. On POSIX it is exact: a spelling difference
//      refuses, it never accepts.
//
// writeConfined then writes to a temporary name opened with the 'wx' flag inside the realpath'd parent and
// renames it over the target, after re-resolving the parent and repeating the containment test. rename()
// replaces a link at the target rather than following it. What remains is a short window between the second
// check and the rename in which another process that can already write inside dist/ could swap a directory for
// a link; that residual is documented in docs/release.md and is not closed here.
import nodeFs from "node:fs";
import nodePath from "node:path";
import { randomBytes } from "node:crypto";

export class Refusal extends Error {}
function refuse(msg) {
  throw new Refusal(msg);
}

const WIN_RESERVED = /^(con|prn|aux|nul|com[1-9\u00b9\u00b2\u00b3]|lpt[1-9\u00b9\u00b2\u00b3]|conin\$|conout\$)$/i;
const WIN_BAD_CHARS = /[<>"|?*\u0000-\u001f]/;

// Rules that only make sense on Windows, applied to the text as typed (before any resolution).
function checkWindowsSyntax(out) {
  const text = out.replace(/\//g, "\\");
  if (/^\\\\[?.]\\/.test(text)) refuse("--out must not be an extended-length or device path (\\\\?\\ or \\\\.\\) on Windows");
  if (text.startsWith("\\\\")) refuse("--out must not be a UNC path on Windows");
  if (/^[A-Za-z]:(?!\\)/.test(text)) refuse("--out must not be a drive-relative path (C:name) on Windows; give a full path or a path relative to the repository");
  const rest = /^[A-Za-z]:\\/.test(text) ? text.slice(3) : text;
  if (rest.includes(":")) refuse("--out must not contain ':' after the drive letter on Windows (alternate data stream)");
  for (const comp of rest.split("\\")) {
    if (comp === "" || comp === ".") continue; // empty from a doubled separator; '.' is normalised away
    if (WIN_BAD_CHARS.test(comp)) refuse(`--out contains a character Windows does not allow in a file name: '${comp.replace(/[\u0000-\u001f]/g, "?")}'`);
    if (/[. ]$/.test(comp)) refuse(`--out components must not end in '.' or ' ' on Windows (Windows strips them): '${comp}'`);
    const stem = comp.split(".")[0].replace(/ +$/, "");
    if (WIN_RESERVED.test(stem)) refuse(`--out must not use a reserved device name (CON, PRN, AUX, NUL, COM1-9, LPT1-9) on Windows: '${comp}'`);
  }
}

function realpathNative(fs, p) {
  return (fs.realpathSync.native || fs.realpathSync)(p);
}

// Is `final` inside `distReal`, strictly below it? rel is computed by the platform's own relative().
function containment(pathMod, distReal, final) {
  const rel = pathMod.relative(distReal, final);
  if (rel === "") refuse("--out must be a file inside dist/");
  if (pathMod.isAbsolute(rel) || rel === ".." || rel.startsWith(".." + pathMod.sep)) {
    refuse(`--out must resolve inside dist/ (resolves to ${final})`);
  }
}

// Returns {target, parent, name, distReal}; throws Refusal. `root` is the repository root as the caller knows it.
export function confineOutput(out, { root, pathMod = nodePath, fs = nodeFs, platform = process.platform } = {}) {
  if (typeof out !== "string" || out === "") refuse("--out must not be empty");
  if (out.includes("\u0000")) refuse("--out must not contain a NUL character");
  if (out.split(/[\\/]/).includes("..")) refuse("--out must not contain '..'");
  if (platform === "win32") checkWindowsSyntax(out);

  const distDir = pathMod.join(root, "dist");
  // A regular file or a dangling link at dist/ must be a one-line refusal, never a stack trace.
  let distReal;
  try {
    fs.mkdirSync(distDir, { recursive: true });
    distReal = realpathNative(fs, distDir);
    if (!fs.lstatSync(distReal).isDirectory()) throw { code: "ENOTDIR" };
  } catch (e) {
    const why = e && (e.code === "EEXIST" || e.code === "ENOTDIR") ? "is not a directory" : e && e.code === "ENOENT" ? "is a dangling link" : `cannot be created (${e && e.code})`;
    refuse(`dist/ ${why}: ${distDir}`);
  }
  const abs = pathMod.resolve(root, out);

  // Deepest existing ancestor; a link or directory at --out itself is refused here.
  let cur = abs;
  for (;;) {
    let st = null;
    try { st = fs.lstatSync(cur); } catch { /* does not exist */ }
    if (st) {
      if (cur === abs) {
        if (st.isSymbolicLink()) refuse(`--out is a symbolic link or junction: ${abs} (refused; the manifest is never written through a link)`);
        if (st.isDirectory()) refuse(`--out is a directory: ${abs}`);
        if (!st.isFile()) refuse(`--out exists and is not a regular file (FIFO, socket or device): ${abs}`);
      } else if (st.isSymbolicLink()) {
        try { realpathNative(fs, cur); } catch { refuse(`--out passes through a dangling symlink: ${cur}`); }
      }
      break;
    }
    const parent = pathMod.dirname(cur);
    if (parent === cur) refuse("--out has no existing ancestor");
    cur = parent;
  }
  const base = realpathNative(fs, cur);
  const final = cur === abs ? base : pathMod.join(base, pathMod.relative(cur, abs));
  containment(pathMod, distReal, final);
  return { target: final, parent: pathMod.dirname(final), name: pathMod.basename(final), distReal };
}

const defaultSuffix = () => randomBytes(6).toString("hex");

// Write `data` to plan.target through a temporary file in the same directory. Throws Refusal if the parent no
// longer resolves inside dist/, or the error from the file system.
export function writeConfined(plan, data, { pathMod = nodePath, fs = nodeFs, randomSuffix = defaultSuffix } = {}) {
  fs.mkdirSync(plan.parent, { recursive: true });
  const parentReal = realpathNative(fs, plan.parent);
  const final = pathMod.join(parentReal, plan.name);
  containment(pathMod, plan.distReal, final);

  let fd;
  let tmp;
  for (let attempt = 0; ; attempt++) {
    tmp = pathMod.join(parentReal, `.release-manifest-${randomSuffix()}.tmp`);
    try {
      fd = fs.openSync(tmp, "wx", 0o666);
      break;
    } catch (e) {
      if (e && e.code === "EEXIST" && attempt < 8) continue; // never overwrite a file that is already there
      throw e;
    }
  }
  try {
    fs.writeFileSync(fd, data);
    fs.fsyncSync(fd);
  } catch (e) {
    try { fs.closeSync(fd); } catch { /* already failing */ }
    try { fs.unlinkSync(tmp); } catch { /* best effort */ }
    throw e;
  }
  fs.closeSync(fd);
  try {
    fs.renameSync(tmp, final);
  } catch (e) {
    try { fs.unlinkSync(tmp); } catch { /* best effort */ }
    throw e;
  }
  return final;
}
