const {test,expect}=require('@playwright/test');
const fs=require('node:fs'),path=require('node:path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
async function boot(page){
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'}));
  window.__DB={products:[],customers:[],invoices:[],invoice_lines:[],profiles:[],suppliers:Array.from({length:235},(_,i)=>({id:'supplier-'+i,name:'Supplier '+String(i).padStart(3,'0'),tax_id:'TAX-'+i,country:'Ecuador',active:true}))};
 });
 await page.route('**/gama-supabase.js*',route=>route.fulfill({contentType:'text/javascript',body:mock}));
 await page.route('**/@supabase/**',route=>route.abort());
 await page.goto('/index.html');
 await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
}
test('the contacts table pages and searches every supplier, and editing preserves unedited fields',async({page})=>{
 await boot(page);await page.evaluate(()=>window.ArcRouter.open('suppliers'));
 await expect(page.locator('#ctTable tbody tr')).toHaveCount(20);
 await expect(page.locator('#ctTable .arcPager')).toContainText('235');
 await page.fill('#ctSearch','Supplier 234');
 await expect(page.locator('#ctTable tbody tr')).toHaveCount(1);
 await expect(page.locator('#ctTable')).toContainText('TAX-234');
 await page.locator('#ctTable [data-ct-edit]').click();await page.fill('#ctf-name','Supplier 234 updated');await page.locator('#ctSave').click();
 await expect.poll(()=>page.evaluate(()=>window.__DB.suppliers.find(s=>s.id==='supplier-234').name)).toBe('Supplier 234 updated');
 expect(await page.evaluate(()=>window.__DB.suppliers.find(s=>s.id==='supplier-234').country)).toBe('Ecuador');
 page.on('dialog',dialog=>dialog.accept());
 await page.locator('#ctTable [data-ct-archive]').click();
 await expect.poll(()=>page.evaluate(()=>window.__DB.suppliers.find(s=>s.id==='supplier-234').active)).toBe(false);
 await page.evaluate(()=>window.GamaArchive.go('contacts','archived'));
 await expect(page.locator('#ctTable [data-ct-restore]')).toBeVisible();await page.locator('#ctTable [data-ct-restore]').click();
 await expect.poll(()=>page.evaluate(()=>window.__DB.suppliers.find(s=>s.id==='supplier-234').active)).toBe(true);
});
test('shared form blocks duplicate requests, reports failures and allows a retry',async({page})=>{
 await boot(page);await page.evaluate(()=>window.ArcRouter.open('suppliers'));
 await page.locator('#ctNew').click();await page.locator('#ctType').selectOption('suppliers');
 await page.fill('#ctf-name','New supplier');
 await page.evaluate(()=>{
  const original=window.GamaCloud.insert;window.__submissions=0;
  // El primer envío se queda en vuelo hasta que la prueba lo suelta: sin un
  // plazo fijo, el botón deshabilitado se comprueba siempre a tiempo.
  window.__release=null;const held=new Promise(r=>window.__release=r);
  window.GamaCloud.insert=async(...args)=>{window.__submissions++;if(window.__submissions===1){await held;return {error:{message:'NETWORK_ERROR'}}}return original(...args);};
  const form=document.getElementById('ctForm');form.requestSubmit();form.requestSubmit();
 });
 await expect(page.locator('#ctSave')).toBeDisabled();expect(await page.evaluate(()=>window.__submissions)).toBe(1);
 await page.evaluate(()=>window.__release());
 await expect(page.locator('#ctMsg')).not.toBeEmpty();await expect(page.locator('#ctSave')).toBeEnabled();
 expect(await page.evaluate(()=>window.__submissions)).toBe(1);await expect(page.locator('#ctf-name')).toHaveValue('New supplier');
 await page.locator('#ctSave').click();
 await expect.poll(()=>page.evaluate(()=>window.__DB.suppliers.filter(s=>s.name==='New supplier').length)).toBe(1);
});
test('optional module loader shares concurrent loads and the router refuses unauthorized entry',async({page})=>{
 await boot(page);
 expect(await page.evaluate(()=>window.GamaFleet.__arcLazy)).toBe(true);
 await page.evaluate(()=>Promise.all([window.ArcLoad('fleet'),window.ArcLoad('fleet')]));
 expect(await page.locator('script[data-arc-module="fleet"]').count()).toBe(1);
 expect(await page.evaluate(()=>!!window.GamaFleet.__arcLazy)).toBe(false);
 expect(await page.evaluate(()=>{const original=window.gamaAccessAllowed;window.gamaAccessAllowed=()=>false;const accepted=window.ArcRouter.open('suppliers');window.gamaAccessAllowed=original;return accepted;})).toBe(false);
});
test('large document lookups bound URL filters and release every module hook',async({page})=>{
 await boot(page);
 const result=await page.evaluate(async()=>{
  const ids=Array.from({length:235},(_,i)=>'invoice-'+i);
  window.__DB.invoice_lines=ids.map((id,i)=>({id:'line-'+i,invoice_id:id,quantity:1}));
  const result=await window.ArcData.byIds('invoice_lines','invoice_id',ids);
  const requests=window.__DB.__calls.filter(c=>c.table==='invoice_lines'&&c.options.in?.invoice_id);
  let closed=0;
  const off1=window.ArcRouter.onEnter('suppliers',()=>()=>closed++),off2=window.ArcRouter.onEnter('suppliers',()=>()=>closed++);
  window.ArcRouter.show('suppliers');window.ArcRouter.show('suppliers');window.ArcRouter.show('mainmenu');off1();off2();
  return {total:result.data.length,maxFilter:Math.max(...requests.map(r=>r.options.in.invoice_id.length)),closed};
 });
 expect(result).toEqual({total:235,maxFilter:100,closed:4});
});
