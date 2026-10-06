const { test, expect } = require("@playwright/test");
const fs = require("node:fs");
const mock = fs.readFileSync(__dirname + "/mock-gama-cloud.js", "utf8");
async function boot(page) {
  await page.addInitScript(() =>
    localStorage.setItem(
      "gama_session_v1",
      JSON.stringify({ role: "admin", name: "PDF QA" }),
    ),
  );
  await page.route("https://**/*", (r) => r.abort());
  await page.route("**/gama-supabase.js*", (r) =>
    r.fulfill({ contentType: "text/javascript", body: mock }),
  );
  await page.goto("/index.html");
  await page.waitForFunction(() => window.GamaRoleAccess?.isReady());
}
test("cold home does not download jsPDF; simultaneous exports generate real PDFs with one engine load", async ({
  page,
}) => {
  const requests = [];
  page.on("request", (r) => {
    if (r.url().includes("/jspdf-")) requests.push(r.url());
  });
  await boot(page);
  expect(requests).toHaveLength(0);
  const result = await page.evaluate(async () => {
    await Promise.all([GamaPdf.ready(), GamaPdf.ready()]);
    const quote = GamaQuotePdf.build({
      number: "QUOTE-QA",
      client: "Test",
      items: [],
      sub: 0,
      tax: 0,
      total: 0,
    });
    const purchase = GamaPurchaseOrderPdf.build({
      number: "PO-QA",
      supplier: "Test",
      items: [],
      total: 0,
    });
    const proof = GamaPdf.proofCertificate({
      cliente: "Test",
      referencia: "DEL-QA",
    }).output("blob");
    return Promise.all(
      [quote, purchase, proof].map(async (b) => ({
        type: b.type,
        header: (await b.text()).slice(0, 4),
        bytes: b.size,
      })),
    );
  });
  expect(requests).toHaveLength(1);
  for (const r of result) {
    expect(r.type).toBe("application/pdf");
    expect(r.header).toBe("%PDF");
    expect(r.bytes).toBeGreaterThan(1000);
  }
});
test("PDF download can recover from an engine network failure without reloading the application", async ({
  page,
}) => {
  await boot(page);
  let attempts = 0;
  await page.route("**/jspdf-4.2.1.umd.min.js*", (r) =>
    ++attempts === 1 ? r.abort() : r.continue(),
  );
  expect(
    await page.evaluate(() =>
      GamaPdf.ready().then(
        () => null,
        (e) => e.message,
      ),
    ),
  ).toBe("MODULE_LOAD_FAILED");
  expect(
    await page.evaluate(async () => {
      await GamaPdf.ready();
      return GamaPdf.proofReport([]).output().slice(0, 4);
    }),
  ).toBe("%PDF");
  expect(attempts).toBe(2);
});
