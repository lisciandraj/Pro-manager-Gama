const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  vm = require("node:vm");
function pdf() {
  const scripts = [],
    handlers = {};
  const window = {
    addEventListener: (name, fn) => {
      handlers[name] = fn;
    },
  };
  const context = {
    window,
    document: {
      createElement: () => ({ dataset: {}, remove() {} }),
      head: { appendChild: (s) => scripts.push(s) },
    },
  };
  vm.createContext(context);
  const loader = fs
    .readFileSync("src/app/loader.js", "utf8")
    .replace(/^import .*;$/gm, "")
    .replace(/^export \{.*;$/gm, "")
    .replace(/export /g, "");
  vm.runInContext(
    loader +
      "\nwindow.ArcLoadScript=loadScript;\n" +
      fs.readFileSync("src/features/documents/pdf.js", "utf8"),
    context,
  );
  return {
    window,
    scripts,
    auth: (event) => handlers["gama:auth-change"]({ detail: { event } }),
  };
}
test("PDF engine stays unloaded until needed, concurrent exports share it and failed loads retry", async () => {
  const x = pdf();
  assert.equal(x.scripts.length, 0);
  const failed = x.window.GamaPdf.ready();
  x.scripts[0].onerror();
  await assert.rejects(failed, /MODULE_LOAD_FAILED/);
  const a = x.window.GamaPdf.ready(),
    b = x.window.GamaPdf.ready();
  assert.equal(x.scripts.length, 2);
  class PDF {}
  x.window.jspdf = { jsPDF: PDF };
  x.scripts[1].onload();
  assert.equal(await a, PDF);
  assert.equal(await b, PDF);
  assert.equal(await x.window.GamaPdf.ready(), PDF);
  assert.equal(x.scripts.length, 2);
});
test("an export waiting for the engine is cancelled when the account changes", async () => {
  const x = pdf(),
    a = x.window.GamaPdf.ready();
  x.auth("SIGNED_OUT");
  x.window.jspdf = { jsPDF: class {} };
  x.scripts[0].onload();
  await assert.rejects(a, /AUTH_CHANGED/);
  assert.equal(await x.window.GamaPdf.ready(), x.window.jspdf.jsPDF);
});
test("token renewal does not cancel an export", async () => {
  const x = pdf(),
    a = x.window.GamaPdf.ready();
  x.auth("TOKEN_REFRESHED");
  x.window.jspdf = { jsPDF: class {} };
  x.scripts[0].onload();
  assert.equal(await a, x.window.jspdf.jsPDF);
});

test("a downloaded script without a PDF engine does not prevent another attempt",async()=>{
 const x=pdf(),first=x.window.GamaPdf.ready();x.scripts[0].onload();
 await assert.rejects(first,/MODULE_LOAD_FAILED/);
 const next=x.window.GamaPdf.ready();assert.equal(x.scripts.length,2);
 class PDF {}x.window.jspdf={jsPDF:PDF};x.scripts[1].onload();assert.equal(await next,PDF);
});
