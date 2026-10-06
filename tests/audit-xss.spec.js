const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
async function boot(page){
 await page.addInitScript(()=>localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'})));
 await page.route('**/gama-supabase.js*',route=>route.fulfill({contentType:'text/javascript',body:cloud}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.ArcRuntimeLoaded&&typeof invoiceHTML==='function');
}
test('malicious quote fields remain text and cannot add elements or event attributes',async({page})=>{
 await boot(page);
 const result=await page.evaluate(()=>{
  const attack='<img src=x onerror="window.__quoteInjection=true">';
  const host=document.createElement('div');host.innerHTML=invoiceHTML({number:attack,seller:attack,sellerRuc:attack,client:attack,clientId:attack,clientAddress:attack,clientEmail:attack,pay:attack,date:'2026-10-06',items:[{name:attack,qty:1,price:10}],sub:10,tax:1.5,total:11.5,rate:15});
  document.body.append(host);return {images:host.querySelectorAll('img').length,text:host.textContent,photo:gamaWorkspacePhoto('data:image/svg+xml;base64,PHN2Zz4='),attrs:host.querySelectorAll('[onerror],[onclick]').length};
 });
 expect(result.images).toBe(0);expect(result.attrs).toBe(0);expect(result.photo).toBe('');expect(result.text).toContain('<img src=x');
 expect(await page.evaluate(()=>window.__quoteInjection)).toBeUndefined();
});
test('CSP blocks inserted inline scripts and handlers while trusted controls still respond',async({page})=>{
 await boot(page);
 await page.evaluate(()=>{
  const script=document.createElement('script');script.textContent='window.__scriptInjection=true';document.body.append(script);
  const button=document.createElement('button');button.id='auditInjected';button.setAttribute('onclick','window.__handlerInjection=true');document.body.append(button);button.click();
  window.removeInvoiceItem=i=>window.__trustedControl=i;
  const trusted=document.createElement('button');trusted.dataset.cocoClick='quote-remove';trusted.dataset.cocoValue='0';document.body.append(trusted);trusted.click();
 });
 expect(await page.evaluate(()=>[window.__scriptInjection,window.__handlerInjection])).toEqual([undefined,undefined]);
 expect(await page.evaluate(()=>window.__trustedControl)).toBe(0);
});
