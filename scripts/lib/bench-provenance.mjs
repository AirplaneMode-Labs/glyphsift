// Provenance for the raw benchmark files under docs/benchmarks/ (owner decision, 20 Nov 2026): every benchmark this
// repository quotes is committed as a raw file that says when it was run, on which commit, on which machine and by
// which command. The benchmark commands (scripts/throughput.mjs, scripts/record-benchmarks.mjs, tests/wasm/run_wasm_safety.mjs,
// tests/demo/check_demo.mjs) import this file, so every raw file has the same envelope:
//
//   { "schema": "glyphsift.benchmark/1", "benchmark": <name>, "date": <UTC, to the second>, "commit": <40 hex>,
//     "build_inputs_modified": <bool>, "worktree_clean": <bool>, "machine": "<model>, <N> GB", "environment": {...},
//     "method": <text>, "command": <text>, "data": {...} }
//
// "commit" is HEAD of the checkout that ran the benchmark. "build_inputs_modified" is true when crates/, Cargo.toml,
// Cargo.lock or rust-toolchain.toml differ from that commit, and then the file does not describe the commit (the
// repository's tests refuse such a file). "machine" is the CPU model and the RAM in whole GB and nothing else: no host
// name, no user name, no serial number, no path. The operating system and tool versions are in "environment".
// Paths are resolved from this file's location; nothing is hard-coded.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { cpus, platform, release, totalmem, version as osVersion } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const SCHEMA = "glyphsift.benchmark/1";
export const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const BUILD_INPUTS = ["crates", "Cargo.toml", "Cargo.lock", "rust-toolchain.toml"];

function run(cmd, args, opts = {}) {
  try {
    return execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], ...opts }).trim();
  } catch {
    return null;
  }
}
const git = (args) => run("git", ["-C", root, ...args]);

export function sha256File(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

/** "<CPU model>, <N> GB": model and RAM only. `override` is the --machine argument, for a machine Node cannot name. */
export function machineLabel(override) {
  if (override) return override;
  const model = (cpus()[0]?.model ?? "unknown CPU").replace(/\s+/g, " ").trim();
  return `${model}, ${Math.round(totalmem() / 2 ** 30)} GB`;
}

function osLabel() {
  if (platform() === "darwin") {
    const v = run("sw_vers", ["-productVersion"]);
    if (v) return `macOS ${v}`;
  }
  return `${osVersion()} ${release()}`.trim();
}

/**
 * Write one raw file: the envelope, then the benchmark's own `method`, `command` and `data`; two-space JSON, LF, one trailing
 * newline. Throws when there is no git checkout, because a raw file records the commit it was run on. Returns the document.
 */
export function writeRaw(path, { benchmark, method, command, data }, { machine, extraEnvironment = {} } = {}) {
  const commit = git(["rev-parse", "HEAD"]);
  if (!commit || !/^[0-9a-f]{40}$/.test(commit)) {
    throw new Error("no git checkout at the repository root: a raw benchmark file records the commit it was run on");
  }
  const status = git(["status", "--porcelain"]);
  const inputs = git(["status", "--porcelain", "--", ...BUILD_INPUTS]);
  const rustc = run("rustc", ["--version"]);
  const doc = {
    schema: SCHEMA,
    benchmark,
    date: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    commit,
    build_inputs_modified: inputs !== "" && inputs !== null,
    worktree_clean: status === "",
    machine: machineLabel(machine),
    environment: { os: osLabel(), node: process.version, ...(rustc ? { rustc } : {}), ...extraEnvironment },
    method,
    command,
    data,
  };
  writeFileSync(path, JSON.stringify(doc, null, 2) + "\n");
  return doc;
}
