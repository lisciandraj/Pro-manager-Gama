const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
// A small static helper page loads the real core utilities without Auth or APIs.
// These are fixtures only; no production identities or documents are used.
test.beforeEach(async({page})=>{
 await page.route('**/security-helper-fixture.html',route=>route.fulfill({contentType:'text/html',body:'<!doctype html><html><body><script type="module">import * as ui from "/src/ui/components.js";window.fixtureUI=ui;window.revoked=[];const revoke=URL.revokeObjectURL.bind(URL);URL.revokeObjectURL=url=>{window.revoked.push(url);revoke(url)};</script></body></html>'}));
 await page.goto('/security-helper-fixture.html');await page.waitForFunction(()=>window.fixtureUI);
});
test('receipt image viewer treats filenames as text and closes/revokes on identity changes',async({page})=>{
 const filename='<img src=x onerror="window.compromised=true">.png';
 // Browser decode must succeed for a real image, not just for a signature fixture.
 const realPng='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aOc8AAAAASUVORK5CYII=';
 await page.evaluate(({png,filename})=>fixtureUI.openAttachment({data_url:'data:image/png;base64,'+png,mime_type:'image/png',filename}),{png:realPng,filename});
 const dialog=page.locator('[data-attachment-viewer]');await expect(dialog).toBeVisible();await expect(dialog.locator('h2')).toHaveText(filename);
 await expect(dialog.locator('img')).toHaveCount(1);await expect.poll(()=>dialog.locator('img').evaluate(img=>img.naturalWidth)).toBe(1);
 expect(await page.evaluate(()=>window.compromised)).toBeUndefined();await expect(dialog.locator('a[download]')).toHaveAttribute('href',/^blob:/);
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'TOKEN_REFRESHED'}})));await expect(dialog).toBeVisible();
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await expect(dialog).toHaveCount(0);expect(await page.evaluate(()=>window.revoked.length)).toBe(1);
});
test('PDF receipt is downloaded as a validated Blob without a popup or document HTML',async({page})=>{
 const bytes='%PDF-1.7\n%%EOF\n',downloadEvent=page.waitForEvent('download');
 await page.evaluate(data=>fixtureUI.openAttachment({data_url:'data:application/pdf;base64,'+btoa(data),mime_type:'application/pdf',filename:'receipt.pdf'}),bytes);
 const download=await downloadEvent;expect(download.suggestedFilename()).toBe('receipt.pdf');expect(fs.readFileSync(await download.path(),'utf8')).toBe(bytes);
 await expect(page.locator('iframe,object,embed,[data-attachment-viewer]')).toHaveCount(0);
 await page.evaluate(()=>window.dispatchEvent(new Event('pagehide')));expect(await page.evaluate(()=>window.revoked.length)).toBe(1);
});
test('stored markup and malformed receipt URLs cannot create a viewer or download',async({page})=>{
 const errors=await page.evaluate(()=>[
  'data:text/html;base64,'+btoa('<script>window.compromised=true</script>'),
  'data:image/svg+xml;base64,'+btoa('<svg onload="window.compromised=true"></svg>'),
  'data:image/png;base64,AAAA" onload="window.compromised=true',
  'data:application/pdf;base64,'+btoa('<html>not a PDF</html>'),
  'https://example.invalid/private.pdf'
 ].map(data_url=>{try{fixtureUI.openAttachment({data_url});return null}catch(error){return error.message}}));
 expect(errors).toEqual(Array(5).fill('DOCUMENT_FILE_INVALID'));expect(await page.evaluate(()=>window.compromised)).toBeUndefined();
 await expect(page.locator('dialog,iframe,object,embed')).toHaveCount(0);expect(await page.evaluate(()=>window.revoked.length)).toBe(0);
});
