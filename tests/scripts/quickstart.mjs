#!/usr/bin/env node
// Extract and run the README's "## Try it in two minutes" blocks, so that the quick start cannot rot (Sprint 7, D3-04; TD-115, TD-116).
//
//   node tests/scripts/quickstart.mjs --self-test                  the parser and the static pre-check on small inputs (no build, no network)
//   node tests/scripts/quickstart.mjs [--readme README.md]          the real run: static pre-check, then every block, then the output comparison
//
// Block convention (the info string of a fenced block inside the section):
//   sh quickstart:setup          run from the repository root with bash: builds the artefacts (it needs the toolchain, not the network of a download)
//   sh quickstart:install        run with bash in a FRESH EMPTY directory outside the clone; $REPO is the clone path (set here)
//   <lang> quickstart:file=NAME  written byte for byte, as UTF-8, into that directory
//   sh quickstart:run            run with bash in that directory; its standard output is collected
//   text quickstart:expect       the exact standard output of the run blocks, compared with LF-normalised lines and trailing whitespace trimmed
//   sh (a plain block)           may hold only the git clone line
// Windows (process.platform === 'win32'): the shell is Git Bash (found from EXEPATH or the Git install folder, never the System32 WSL launcher; see gitBashCandidates), `.venv/bin/`
// is read as `.venv/Scripts/` and `python3` as `python` (the README says so in one sentence).
//
// Static pre-check (a failure is exit 1 before anything runs): in every block except the git clone line, none of: http://, https://, curl, wget,
// Invoke-WebRequest, a pipe into sh or bash, sudo, npx, allowTestKeys, --allow-test-key, --trust-test-key, rfc8032, 'unsafe-', a Content-Security-Policy edit. A plain
// sh block that is anything but one git clone line, an unknown quickstart: tag, or a section without setup, install, file, run and expect blocks fails too.
// Each block runs with a scrubbed environment (buildEnv, checked by the self-test): PATH, HOME (USERPROFILE on Windows), TEMP and TMP, SYSTEMROOT on Windows, REPO,
// npm_config_offline=true, a fresh npm_config_cache, PIP_NO_INDEX=1, PIP_DISABLE_PIP_VERSION_CHECK=1, PYTHON (the caller's, else `python` on Windows, where python3 is not
// installed and scripts/package-npm.sh reads ${PYTHON:-python3}), and on Windows the system variables in WIN_SYSTEM_VARS (ProgramFiles(x86), ProgramData, windir, ComSpec,
// PATHEXT ...: the linker lookup and Node read them). No GITHUB_* variable and no CI.
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, posix, relative, resolve, win32 } from "node:path";
import { fileURLToPath } from "node:url";

const SECTION = "## Try it in two minutes";
const WIN_SYSTEM_VARS = ["windir", "ComSpec", "PATHEXT", "ProgramFiles", "ProgramFiles(x86)", "ProgramW6432", "ProgramData", "CommonProgramFiles", "CommonProgramFiles(x86)", "CommonProgramW6432",
  "ALLUSERSPROFILE", "APPDATA", "LOCALAPPDATA", "NUMBER_OF_PROCESSORS", "PROCESSOR_ARCHITECTURE", "OS"];
const TAGS = new Set(["setup", "install", "run", "expect"]);
const FORBIDDEN = [
  [/http:\/\//i, "http://"],
  [/https:\/\//i, "https://"],
  [/\bcurl\b/i, "curl"],
  [/\bwget\b/i, "wget"],
  [/Invoke-WebRequest/i, "Invoke-WebRequest"],
  [/\|\s*(ba)?sh\b/, "a pipe into sh or bash"],
  [/\bsudo\b/, "sudo"],
  [/\bnpx\b/, "npx"],
  [/allowTestKeys/, "allowTestKeys"],
  [/--allow-test-key/, "--allow-test-key"],
  [/--trust-test-key/, "--trust-test-key"],
  [/rfc8032/i, "rfc8032"],
  [/unsafe-/, "unsafe-"],
  [/Content-Security-Policy/i, "a Content-Security-Policy edit"],
];

/** The fenced blocks of the section, in order: { info, body }. */
export function extractBlocks(readme) {
  const lines = readme.replace(/\r\n/g, "\n").split("\n");
  const start = lines.findIndex((l) => l === SECTION);
  if (start < 0) throw new Error(`the README has no '${SECTION}' section`);
  const blocks = [];
  let open = null;
  for (let i = start + 1; i < lines.length; i += 1) {
    const l = lines[i];
    if (open === null) {
      if (/^## /.test(l)) break;
      const m = /^```(.*)$/.exec(l);
      if (m) open = { info: m[1].trim(), body: [] };
    } else if (l === "```") {
      blocks.push({ info: open.info, body: open.body.join("\n") + "\n" });
      open = null;
    } else open.body.push(l);
  }
  if (open !== null) throw new Error("a fenced block in the section is not closed");
  return blocks;
}

/** Classify a block by its info string: { kind, name? } or throws. */
export function classify(block) {
  const parts = block.info.split(/\s+/).filter(Boolean);
  if (parts.length === 0) throw new Error("a fenced block in the section has no info string");
  const tag = parts.slice(1).find((p) => p.startsWith("quickstart:"));
  if (!tag) {
    if (parts.length === 1 && parts[0] === "sh") return { kind: "plain" };
    throw new Error(`block '${block.info}' has no quickstart: tag and is not a plain sh block`);
  }
  if (parts.length !== 2) throw new Error(`block '${block.info}': the info string is '<lang> quickstart:<tag>'`);
  const t = tag.slice("quickstart:".length);
  if (t.startsWith("file=")) {
    const name = t.slice(5);
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) throw new Error(`block '${block.info}': a file name is letters, digits, dot, dash and underscore only`);
    return { kind: "file", name };
  }
  if (!TAGS.has(t)) throw new Error(`block '${block.info}': unknown tag quickstart:${t}`);
  if ((t === "setup" || t === "install" || t === "run") && parts[0] !== "sh") throw new Error(`block '${block.info}': a ${t} block is an sh block`);
  if (t === "expect" && parts[0] !== "text") throw new Error(`block '${block.info}': the expect block is a text block`);
  return { kind: t };
}

/** The pre-check: an array of problems (empty when the section is fine). */
export function preCheck(readme) {
  const problems = [];
  let blocks;
  try { blocks = extractBlocks(readme); } catch (e) { return [e.message]; }
  const kinds = new Set();
  for (const b of blocks) {
    let c;
    try { c = classify(b); } catch (e) { problems.push(e.message); continue; }
    kinds.add(c.kind);
    if (c.kind === "plain") {
      const code = b.body.split("\n").filter((l) => l.trim() !== "");
      if (code.length !== 1 || !/^git clone https:\/\/github\.com\/AirplaneMode-Labs\/glyphsift\.git$/.test(code[0].trim())) problems.push(`a plain sh block may hold only the git clone line (got ${JSON.stringify(code.join(" | ").slice(0, 80))})`);
      continue;
    }
    for (const [re, name] of FORBIDDEN) if (re.test(b.body)) problems.push(`block '${b.info}' contains ${name}`);
  }
  for (const need of ["setup", "install", "file", "run", "expect"]) if (!kinds.has(need)) problems.push(`the section has no ${need} block`);
  return problems;
}

const normalise = (s) => s.replace(/\r\n/g, "\n").split("\n").map((l) => l.replace(/\s+$/, "")).join("\n").replace(/\n+$/, "");

/**
 * Candidate paths of the Git for Windows bash.exe, best first (always path.win32 spelling, so that the self-test can run them on any host).
 * EXEPATH is the Git root when Git Bash is started from git-bash.exe, but the directory of the launcher (C:\Program Files\Git\bin) when it is started as
 * C:\Program Files\Git\bin\bash.exe, which is how a GitHub Actions `shell: bash` step starts it (CI run 44651027362): both are handled, then the install folders.
 */
export function gitBashCandidates(procEnv) {
  const out = [];
  const add = (c) => { if (!out.includes(c)) out.push(c); };
  if (procEnv.EXEPATH) {
    if (win32.basename(procEnv.EXEPATH).toLowerCase() === "bin") add(win32.join(procEnv.EXEPATH, "bash.exe"));
    else add(win32.join(procEnv.EXEPATH, "bin", "bash.exe"));
  }
  for (const pf of [procEnv.ProgramW6432, procEnv.ProgramFiles, procEnv["ProgramFiles(x86)"]]) if (pf) add(win32.join(pf, "Git", "bin", "bash.exe"));
  if (procEnv.LOCALAPPDATA) add(win32.join(procEnv.LOCALAPPDATA, "Programs", "Git", "bin", "bash.exe"));
  return out;
}

/** The first candidate that exists, or null. Never the System32 launcher (WSL) and never a bare `bash` looked up on PATH. */
export function findGitBash(procEnv, exists) {
  for (const c of gitBashCandidates(procEnv)) if (exists(c)) return c;
  return null;
}

/** The scrubbed environment of every block (see the header). `win` picks the path flavour, so the self-test can build the Windows one anywhere. */
export function buildEnv(procEnv, win, root, scratch, cache) {
  const P = win ? win32 : posix;
  const sep = win ? ";" : ":";
  const env = { PATH: procEnv.PATH ?? "", REPO: win ? root.replace(/\\/g, "/") : root, npm_config_offline: "true", npm_config_cache: cache, PIP_NO_INDEX: "1", PIP_DISABLE_PIP_VERSION_CHECK: "1", TEMP: scratch, TMP: scratch, TMPDIR: scratch };
  // The real HOME (USERPROFILE on Windows) is kept: scripts/remap-paths.sh remaps $HOME/.cargo and $HOME/.rustup out of the builds, and the builder-path gate of
  // scripts/package-npm.sh fails if a /home/<user> or C:\\Users path survives; a scratch HOME would hide the real cargo directory from the remap.
  const realHome = procEnv.HOME ?? procEnv.USERPROFILE ?? scratch;
  if (win) {
    env.USERPROFILE = procEnv.USERPROFILE ?? realHome; env.SYSTEMROOT = procEnv.SYSTEMROOT ?? "C:\\Windows"; env.HOME = procEnv.HOME ?? realHome;
    // System variables that the MSVC linker lookup, cmd and Node read; none of them carries a secret or a CI setting.
    for (const k of WIN_SYSTEM_VARS) if (procEnv[k] !== undefined) env[k] = procEnv[k];
  } else env.HOME = realHome;
  // The interpreter the scripts use (scripts/package-npm.sh reads ${PYTHON:-python3}): CI sets PYTHON=python on Windows, where python3 is not installed.
  if (procEnv.PYTHON) env.PYTHON = procEnv.PYTHON; else if (win) env.PYTHON = "python";
  // a tool venv for maturin, when CI or the developer gave one (the hashed venv of tools/ci/requirements.txt): its bin directory goes first on PATH
  const tv = procEnv.GLYPHSIFT_TOOLS_VENV;
  if (tv) env.PATH = [P.join(tv, win ? "Scripts" : "bin"), env.PATH].join(sep);
  // Rust and Node tools live under HOME (cargo, rustup) on a developer machine: keep them reachable without keeping the rest of the environment
  if (procEnv.CARGO_HOME) env.CARGO_HOME = procEnv.CARGO_HOME; else if (procEnv.HOME) env.CARGO_HOME = P.join(procEnv.HOME, ".cargo");
  if (procEnv.RUSTUP_HOME) env.RUSTUP_HOME = procEnv.RUSTUP_HOME; else if (procEnv.HOME) env.RUSTUP_HOME = P.join(procEnv.HOME, ".rustup");
  if (env.CARGO_HOME) env.PATH = [P.join(env.CARGO_HOME, "bin"), env.PATH].join(sep);
  return env;
}

function selfTest() {
  let bad = 0;
  const check = (ok, what) => { console.log(`${ok ? "ok   " : "FAIL "} ${what}`); if (!ok) bad += 1; };
  const good = [
    SECTION, "", "```sh", "git clone https://github.com/AirplaneMode-Labs/glyphsift.git", "```", "```sh quickstart:setup", "cargo build --release --locked -p glyphsift-cli", "```",
    "```sh quickstart:install", "python3 -m venv .venv", "```", "```py quickstart:file=q.py", "print('x')", "```", "```sh quickstart:run", ".venv/bin/python q.py", "```",
    "```text quickstart:expect", "x", "```", "## Next", "",
  ].join("\n");
  check(preCheck(good).length === 0, "a well-formed section passes the pre-check");
  check(extractBlocks(good).length === 6, "six blocks are extracted and the next section is not read");
  const bads = [
    ["http://", "curl http://x"], ["https://", "echo https://example.org"], ["curl", "curl -s x"], ["wget", "wget x"], ["Invoke-WebRequest", "Invoke-WebRequest x"],
    ["a pipe into sh or bash", "echo x | sh"], ["a pipe into sh or bash", "echo x | bash"], ["sudo", "sudo ls"], ["npx", "npx serve"], ["allowTestKeys", "allowTestKeys: true"],
    ["--allow-test-key", "tool --allow-test-key"], ["--trust-test-key", "tool --trust-test-key"], ["rfc8032", "rfc8032-1"], ["unsafe-", "script-src 'unsafe-inline'"],
    ["a Content-Security-Policy edit", "Content-Security-Policy: x"],
  ];
  for (const [what, line] of bads) {
    const doc = good.replace("python3 -m venv .venv", line);
    const p = preCheck(doc);
    check(p.some((m) => m.includes(what)), `the pre-check refuses ${what} in an install block`);
    const doc2 = good.replace("print('x')", line);
    check(preCheck(doc2).some((m) => m.includes(what)), `the pre-check refuses ${what} in a file block`);
  }
  check(preCheck(good.replace("git clone https://github.com/AirplaneMode-Labs/glyphsift.git", "git clone https://github.com/AirplaneMode-Labs/glyphsift.git && cd glyphsift")).some((m) => m.includes("plain sh block")), "a plain sh block holds only the git clone line");
  check(preCheck(good.replace("git clone https://github.com/AirplaneMode-Labs/glyphsift.git", "curl x")).some((m) => m.includes("plain sh block")), "a plain sh block with anything else is refused");
  check(preCheck(good.replace("quickstart:run", "quickstart:runn")).some((m) => m.includes("unknown tag")), "an unknown quickstart: tag is refused");
  check(preCheck(good.replace("```sh quickstart:run", "```bash quickstart:run")).some((m) => m.includes("an run block is an sh block") || m.includes("run block is an sh block")), "a run block must be an sh block");
  check(preCheck(good.replace("```py quickstart:file=q.py", "```py quickstart:file=../q.py")).some((m) => m.includes("file name")), "a file name with a path is refused");
  check(preCheck(good.replace(/```text quickstart:expect\nx\n```\n/, "")).some((m) => m.includes("no expect block")), "a section without an expect block is refused");
  check(preCheck("# nothing\n").some((m) => m.includes("no '## Try it in two minutes' section")), "a README without the section is refused");
  check(normalise("a  \r\nb\n\n") === "a\nb", "the comparison normalises CRLF, trailing whitespace and trailing blank lines");
  check(normalise("a\nb") !== normalise("a\nc"), "the comparison still tells different output apart");

  // Windows, checked on any host with path.win32 (CI run 44651027362, release-rehearsal on windows-latest: "spawnSync C:\Program Files\Git\bin\bin\bash.exe ENOENT").
  // The runner's step shell is C:\Program Files\Git\bin\bash.EXE and Git Bash sets EXEPATH to the directory of that launcher, not to the Git root.
  const GIT_BASH = "C:\\Program Files\\Git\\bin\\bash.exe";
  const onlyThere = (...files) => (p) => files.includes(p);
  check(findGitBash({ EXEPATH: "C:\\Program Files\\Git\\bin" }, onlyThere(GIT_BASH)) === GIT_BASH, "Windows: EXEPATH naming the bin directory (what the runner's shell sets) finds bin\\bash.exe, not bin\\bin\\bash.exe");
  check(findGitBash({ EXEPATH: "C:\\Program Files\\Git" }, onlyThere(GIT_BASH)) === GIT_BASH, "Windows: EXEPATH naming the Git root finds bin\\bash.exe");
  check(findGitBash({ ProgramFiles: "C:\\Program Files" }, onlyThere(GIT_BASH)) === GIT_BASH, "Windows: without EXEPATH, the Git folder under ProgramFiles is used");
  check(findGitBash({ EXEPATH: "C:\\Program Files\\Git\\bin", ProgramFiles: "C:\\Program Files" }, () => false) === null, "Windows: no Git Bash on disk gives null (a clear failure), not a bare 'bash' from PATH");
  check(findGitBash({ EXEPATH: "C:\\Program Files\\Git\\bin" }, onlyThere("C:\\Windows\\System32\\bash.exe")) === null, "Windows: the System32 bash.exe (the WSL launcher) is never chosen");
  check(gitBashCandidates({ EXEPATH: "C:\\Program Files\\Git\\bin" }).every((c) => !/\\bin\\bin\\/.test(c)), "Windows: no candidate path repeats the bin directory");

  // The environment of the blocks. CI sets PYTHON=python on Windows (python3 is not there) and scripts/package-npm.sh reads ${PYTHON:-python3}: a scrubbed
  // environment must keep that choice, or the setup block fails on Windows at the builder-path gate.
  const ci = { PATH: "C:\\Windows\\system32;C:\\hostedtoolcache\\Python", HOME: "C:\\Users\\runneradmin", USERPROFILE: "C:\\Users\\runneradmin", SYSTEMROOT: "C:\\Windows", CARGO_HOME: "C:\\Users\\runneradmin\\.cargo",
    GLYPHSIFT_TOOLS_VENV: "D:\\a\\_temp/tools-venv", PYTHON: "python", GITHUB_TOKEN: "not-a-real-token", GITHUB_ACTIONS: "true", CI: "true", RUNNER_TEMP: "D:\\a\\_temp", ACTIONS_ID_TOKEN_REQUEST_TOKEN: "x",
    "ProgramFiles(x86)": "C:\\Program Files (x86)", ProgramData: "C:\\ProgramData", windir: "C:\\Windows", ComSpec: "C:\\Windows\\system32\\cmd.exe", PATHEXT: ".COM;.EXE", SOME_OTHER_VARIABLE: "kept out" };
  const wEnv = buildEnv(ci, true, "D:\\a\\glyphsift\\glyphsift", "D:\\a\\_temp\\gs", "D:\\a\\_temp\\gs\\npm-cache");
  check(wEnv.PYTHON === "python", "Windows: PYTHON=python reaches the blocks");
  check(buildEnv({ ...ci, PYTHON: undefined }, true, "D:\\r", "D:\\s", "D:\\c").PYTHON === "python", "Windows: PYTHON defaults to python (python3 is not on the runner) when the caller set none");
  check(buildEnv({ PATH: "/usr/bin", HOME: "/home/u" }, false, "/r", "/s", "/c").PYTHON === undefined, "POSIX: PYTHON stays unset, so the scripts use python3");
  check(buildEnv({ PATH: "/usr/bin", HOME: "/home/u", PYTHON: "python3.12" }, false, "/r", "/s", "/c").PYTHON === "python3.12", "POSIX: a PYTHON the caller set is kept");
  check(Object.keys(wEnv).every((k) => !/^(GITHUB_|RUNNER_|ACTIONS_|CI$)/i.test(k) && !/TOKEN/i.test(k)), "Windows: no GITHUB_*, RUNNER_*, ACTIONS_*, CI or *TOKEN* variable reaches the blocks");
  check(wEnv["ProgramFiles(x86)"] === "C:\\Program Files (x86)" && wEnv.ProgramData === "C:\\ProgramData" && wEnv.windir === "C:\\Windows" && wEnv.ComSpec !== undefined && wEnv.PATHEXT === ".COM;.EXE", "Windows: the system variables the MSVC linker and Node look up are kept (ProgramFiles(x86), ProgramData, windir, ComSpec, PATHEXT)");
  check(wEnv.SOME_OTHER_VARIABLE === undefined, "Windows: any other variable is still scrubbed");
  check(wEnv.PATH.startsWith("C:\\Users\\runneradmin\\.cargo\\bin;D:\\a\\_temp\\tools-venv\\Scripts;C:\\Windows\\system32;"), "Windows: PATH is the cargo bin, the tool venv's Scripts directory, then the caller's PATH");
  check(wEnv.REPO === "D:/a/glyphsift/glyphsift", "Windows: REPO is spelled with forward slashes for bash");
  console.log(bad === 0 ? "quickstart self-test: all checks passed" : `quickstart self-test: ${bad} FAILED`);
  return bad === 0 ? 0 : 1;
}

function main() {
  const argv = process.argv.slice(2);
  if (argv.includes("--self-test")) process.exit(selfTest());
  const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
  const readmePath = argv.includes("--readme") ? resolve(argv[argv.indexOf("--readme") + 1]) : join(root, "README.md");
  const readme = readFileSync(readmePath, "utf8");
  const problems = preCheck(readme);
  if (problems.length) {
    for (const p of problems) console.log(`FAIL pre-check: ${p}`);
    process.exit(1);
  }
  console.log("ok   static pre-check passed");
  const win = process.platform === "win32";
  const fix = (body) => (win ? body.replace(/\.venv\/bin\//g, ".venv/Scripts/").replace(/\bpython3\b/g, "python") : body);

  const scratch = realpathSync(mkdtempSync(join(tmpdir(), "glyphsift-quickstart-")));
  const work = join(scratch, "work");
  const cache = join(scratch, "npm-cache");
  mkdirSync(work);
  mkdirSync(cache);
  const rel = relative(realpathSync(root), work);
  if (!(rel.startsWith("..") || isAbsolute(rel))) { console.log("FAIL the work directory is inside the clone"); process.exit(1); }
  const env = buildEnv(process.env, win, root, scratch, cache);

  const blocks = extractBlocks(readme).map((b) => ({ ...b, ...classify(b) }));
  let out = "";
  let failures = 0;
  const bashExe = win ? findGitBash(process.env, existsSync) : "bash";
  if (bashExe === null) { console.log(`FAIL no Git Bash found (looked at: ${gitBashCandidates(process.env).join(", ")}); the blocks are run in Git Bash on Windows`); process.exit(1); }
  const bash = (script, cwd, label) => {
    const r = spawnSync(bashExe, ["-euo", "pipefail", "-c", fix(script)], { cwd, env, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
    if (r.status !== 0) {
      failures += 1;
      console.log(`FAIL ${label}: exit ${r.status}${r.error ? " (" + r.error.message + ")" : ""}`);
      console.log((r.stdout ?? "").split("\n").slice(-12).map((l) => "    | " + l).join("\n"));
      console.log((r.stderr ?? "").split("\n").slice(-12).map((l) => "    ! " + l).join("\n"));
      return null;
    }
    console.log(`ok   ${label}`);
    return r.stdout;
  };
  let expected = null;
  for (const b of blocks) {
    if (failures) break;
    if (b.kind === "plain") console.log("ok   the git clone line is not run (the clone is the working tree under test)");
    else if (b.kind === "setup") bash(b.body, root, "setup block (from the repository root)");
    else if (b.kind === "install") bash(b.body, work, "install block (a fresh empty directory outside the clone)");
    else if (b.kind === "file") { writeFileSync(join(work, b.name), b.body, "utf8"); console.log(`ok   wrote ${b.name} (${b.body.length} characters)`); }
    else if (b.kind === "run") { const o = bash(b.body, work, "run block"); if (o !== null) out += o; }
    else if (b.kind === "expect") expected = b.body;
  }
  if (!failures) {
    if (expected === null) { failures += 1; console.log("FAIL no expect block"); }
    else if (normalise(out) !== normalise(expected)) {
      failures += 1;
      console.log("FAIL the output of the run blocks differs from the expect block");
      console.log("  expected:\n" + normalise(expected).split("\n").map((l) => "    " + l).join("\n"));
      console.log("  got:\n" + normalise(out).split("\n").map((l) => "    " + l).join("\n"));
    } else console.log(`ok   the output equals the expect block (${normalise(expected).split("\n").length} lines)`);
  }
  try { rmSync(scratch, { recursive: true, force: true }); } catch { /* a Windows file lock is not a test result */ }
  console.log(failures === 0 ? "quickstart: all blocks ran and the output matched" : `quickstart: ${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
