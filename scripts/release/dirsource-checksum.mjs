#!/usr/bin/env node
// Write the .cargo-checksum.json that cargo's directory source wants, for ONE unpacked packaged crate (Sprint 7, D3-02).
//
//   node scripts/release/dirsource-checksum.mjs <the .crate file> <the directory the .crate was unpacked into>
//
// The file is {"files": {<path relative to the crate directory, forward slashes>: <sha256 of that file>}, "package": <sha256 of the .crate>}.
// `package` is what the crate's Cargo.lock records as its checksum, so a .crate that was changed after packaging no longer matches the lock and
// cargo refuses it. The file never lists itself. Standard library only. Exit 0 on success, 1 on any error.
import { createHash } from "node:crypto";
import { lstatSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const [crate, dir] = process.argv.slice(2);
if (!crate || !dir) {
  console.error("usage: dirsource-checksum.mjs <file.crate> <unpacked dir>");
  process.exit(2);
}
const sha = (b) => createHash("sha256").update(b).digest("hex");
const files = {};
function walk(rel) {
  for (const name of readdirSync(join(dir, rel)).sort()) {
    const r = rel === "" ? name : `${rel}/${name}`;
    const st = lstatSync(join(dir, r));
    if (st.isSymbolicLink()) throw new Error(`${r} is a link`);
    if (st.isDirectory()) walk(r);
    else if (st.isFile()) {
      if (r !== ".cargo-checksum.json") files[r] = sha(readFileSync(join(dir, r)));
    } else throw new Error(`${r} is not a regular file`);
  }
}
try {
  walk("");
  const sorted = Object.fromEntries(Object.keys(files).sort().map((k) => [k, files[k]]));
  const out = JSON.stringify({ files: sorted, package: sha(readFileSync(crate)) });
  writeFileSync(join(dir, ".cargo-checksum.json"), out);
  console.log(`wrote ${join(dir, ".cargo-checksum.json")} (${Object.keys(sorted).length} files, package ${sha(readFileSync(crate))})`);
} catch (e) {
  console.error(`dirsource-checksum: ${e.message}`);
  process.exit(1);
}
