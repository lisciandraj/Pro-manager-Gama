const {test,expect}=require('@playwright/test'),path=require('node:path');
const modulePath=path.join(__dirname,'../src/features/finance/invoice-tools.js');
async function setup(page){
 await page.route('**/__invoice_tools_test',r=>r.fulfill({contentType:'text/html',body:'<!doctype html><html lang="fr"><body></body></html>'}));await page.goto('/__invoice_tools_test');
 await page.evaluate(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({userId:'account-a',role:'admin'}));window.__calls=[];window.__permissions=['accounting','sri','payments','sales-orders'];window.gamaAccessAllowed=p=>__permissions.includes(p);window.GamaI18n={language:'fr',t:t=>t};
  window.ArcLoadScript=async asset=>{__calls.push(['load',asset]);if(window.__waitingAsset===asset)await new Promise(r=>window.__release=r)};
  window.GamaInternalInvoices={pdf:async i=>__calls.push(['pdf',i.id]),link:async(id,done)=>__calls.push(['link',id,done===window.__done]),view:async(id,done)=>__calls.push(['view',id,done===window.__done])};
  window.GamaAccounting={openSri:id=>__calls.push(['sri',id])};window.CocoInvoiceDeferrals={showPlans:async(side,id)=>__calls.push(['deferrals',side,id])};window.CocoSalesRewards={invoice:(id,done)=>{__calls.push(['rewards',id]);window.__rewardDone=done}};window.CocoInvoiceCheckout={open:i=>__calls.push(['payment',i.id])};
  Object.defineProperty(navigator,'clipboard',{value:{writeText:async text=>__calls.push(['copy',text])},configurable:true});window.__done=()=>{};
  window.__invoice={id:'i1',number:'INV-1',issue_date:'2026-11-08',subtotal:10,tax:1.5,total:11.5,document_snapshot:{customer:'Andes',customer_identification:'0991',quote_number:'Q-1',order_number:'SO-1',lines:[{name:'Toner',reference:'TN',qty:1,price:10,taxRate:15,subtotal:10,tax:1.5}]}};
  window.__dialog=()=>{const d=document.createElement('dialog');d.innerHTML='<div class="gsActions"><button id="giLink" disabled>Link</button><button id="giPdf" disabled>PDF</button><button id="giCopy" disabled>Copy</button></div><textarea id="giText"></textarea><p id="giCopyStatus"></p><p id="gsFormError"></p>';document.body.append(d);d.showModal();return d};
 });
}
test('lazy invoice tools preserve exports, copy data, payment and gift refresh',async({page})=>{
 await setup(page);await page.addScriptTag({path:modulePath});await page.evaluate(()=>CocoInvoiceTools.attach(__invoice,__dialog(),__done));
 await expect(page.locator('#giPdf')).toBeEnabled();await expect(page.locator('#giText')).toHaveValue(/FACTURA INTERNA INV-1[\s\S]*Toner\tTN/);await page.click('#giCopy');await expect(page.locator('#giCopyStatus')).toHaveText('Datos copiados.');await page.click('#giPdf');await page.click('#giPaymentLink');await page.click('#giRewards');await page.evaluate(()=>__rewardDone());
 expect(await page.evaluate(()=>__calls)).toEqual(expect.arrayContaining([['pdf','i1'],['payment','i1'],['rewards','i1'],['view','i1',true],['load','coco-invoice-checkout.js'],['load','coco-sales-rewards.js']]));
 await page.evaluate(()=>CocoInvoiceTools.attach(__invoice,__dialog(),__done));await page.locator('dialog[open] #giLink').click();expect(await page.evaluate(()=>__calls.at(-1))).toEqual(['link','i1',true]);
});
test('SRI and deferrals retain permissions and cancelled documents exclude gifts and payment',async({page})=>{
 await setup(page);await page.addScriptTag({path:modulePath});await page.evaluate(()=>{__invoice.fiscal_status='cancelled';CocoInvoiceTools.attach(__invoice,__dialog(),__done)});await expect(page.locator('#giRewards')).toHaveCount(0);await expect(page.locator('#giPaymentLink')).toHaveCount(0);await page.click('#giDeferrals');expect(await page.evaluate(()=>__calls.at(-1))).toEqual(['deferrals','customer','i1']);
 await page.evaluate(()=>{CocoInvoiceTools.attach(__invoice,__dialog(),__done)});await page.locator('dialog[open] #giSri').click();expect(await page.evaluate(()=>__calls.at(-1))).toEqual(['sri','i1']);
 await page.evaluate(()=>{__permissions=['sales-orders'];CocoInvoiceTools.attach(__invoice,__dialog(),__done)});await expect(page.locator('dialog[open] #giSri')).toHaveCount(0);await expect(page.locator('dialog[open] #giDeferrals')).toHaveCount(0);await expect(page.locator('dialog[open] #giPdf')).toBeEnabled();
});
test('logout while an action asset loads prevents stale invoice actions',async({page})=>{
 await setup(page);await page.addScriptTag({path:modulePath});await page.evaluate(()=>{__waitingAsset='coco-sales-rewards.js';CocoInvoiceTools.attach(__invoice,__dialog(),__done)});await page.click('#giRewards');await expect.poll(()=>page.evaluate(()=>typeof __release)).toBe('function');await page.evaluate(()=>{localStorage.removeItem('gama_session_v1');window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}}));__release()});await expect(page.locator('[data-coco-invoice-tool]')).toHaveCount(0);expect(await page.evaluate(()=>__calls.some(c=>c[0]==='rewards'))).toBe(false);
});
test('invoice view waits for lazy tools and drops an attachment after logout',async({page})=>{
 await setup(page);await page.evaluate(()=>{
  window.ArcUI={esc:s=>String(s??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;')};window.ArcFormat={money:n=>String(n)};
  __invoice.document_kind='internal';window.GamaSales={rows:async()=>[__invoice],modal:(_title,body)=>{const d=document.createElement('dialog');d.innerHTML=body+'<p id="gsFormError"></p>';document.body.append(d);d.showModal();return d}};
  window.ArcLoadScript=async()=>{await new Promise(r=>window.__release=r)};
 });await page.addScriptTag({path:path.join(__dirname,'../src/features/sales/internal-invoices.js')});await page.evaluate(()=>GamaInternalInvoices.view('i1',__done));await expect(page.locator('#giPdf')).toBeDisabled();await expect(page.locator('#giCopy')).toBeDisabled();await page.addScriptTag({path:modulePath});await page.evaluate(()=>{window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}}));__release()});await expect(page.locator('#giPdf')).toBeDisabled();await expect(page.locator('#giPaymentLink')).toHaveCount(0);
});
