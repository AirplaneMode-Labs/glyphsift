// Helper for tests/scripts/npm-publish-arg.sh (S1-130): resolves each argument with the npm-package-arg module that ships inside the npm of the running Node, the
// module `npm publish <spec>` itself uses, and prints one line per argument: `<spec>\t<type>\t<detail>`. Exit 3 when the module cannot be found.
//   node tests/scripts/npm-package-arg-probe.cjs <spec>...
const fs = require("fs");
const path = require("path");
const real = fs.realpathSync(process.execPath);
const candidates = [
  path.join(path.dirname(real), "..", "lib", "node_modules", "npm", "node_modules", "npm-package-arg"), // Linux and macOS installs
  path.join(path.dirname(real), "node_modules", "npm", "node_modules", "npm-package-arg"), // the Windows installer's layout
];
let npa = null;
for (const c of candidates) {
  try { npa = require(c); break; } catch (e) { /* try the next layout */ }
}
if (!npa) { console.error("npm-package-arg not found next to " + real); process.exit(3); }
for (const spec of process.argv.slice(2)) {
  const r = npa(spec);
  const detail = r.hosted ? "hosted " + r.hosted.type + ":" + r.hosted.user + "/" + r.hosted.project : (r.fetchSpec || "");
  console.log(spec + "\t" + r.type + "\t" + detail);
}
