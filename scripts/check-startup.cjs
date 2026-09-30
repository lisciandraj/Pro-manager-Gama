// Static payload budget, not a latency benchmark. Run after npm run build.
const fs = require("node:fs");
const path = require("node:path");
const { gzipSync } = require("node:zlib");
const root = path.resolve(__dirname, "..");
const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
const sources = [...html.matchAll(/<script\b[^>]*\bsrc=["']([^"']+)["']/g)].map(
  (m) => m[1],
);
let bytes = 0,
  gzipBytes = 0;
for (const source of sources) {
  if (/^(?:https?:)?\/\//.test(source))
    throw Error("Unbudgeted external startup script: " + source);
  const data = fs.readFileSync(path.join(root, source.split("?")[0]));
  bytes += data.length;
  gzipBytes += gzipSync(data).length;
}
const result = {
  scripts: sources.length,
  bytes,
  gzipBytes,
  budgetBytes: 1900000,
  budgetScripts: 93,
};
console.log(JSON.stringify(result, null, 2));
if (bytes > result.budgetBytes || sources.length > result.budgetScripts) {
  throw Error(
    "Startup JavaScript budget exceeded. Review eager dependencies before increasing the budget.",
  );
}
