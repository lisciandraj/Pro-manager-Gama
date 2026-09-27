const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
async function boot(page){
 await page.addInitScript(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'}));window.__DB={products:[{id:'p1',name:'Café',active:true}],customers:[],suppliers:[],profiles:[],invoices:[]}});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');await page.waitForFunction(()=>window.ArchitectStockAudit&&window.ArcData);
 await page.evaluate(async()=>{await GamaCloudReady;window.__auditCalls=[];const rpc=ArcData.rpc;window.ArcData={...ArcData,rpc:async(name,args)=>{
  if(!['gama_integrity','gama_valuation','gama_technical_checks'].includes(name))return rpc(name,args);
  __auditCalls.push({name,...args});const d=args.p_data||{};
  if(name==='gama_integrity')return {total:1,items:[{id:'p1',reference:'CAFE',name:'Café',catalogue_quantity:5,located_quantity:0,missing:['supplier','replenishment'],replenishment_excluded:false,cases:[{id:'case1',catalogue_quantity:5,located_quantity:0}]}]};
  if(name==='gama_technical_checks')return {stock_mismatches:25,historical_cases:25,valuation_mismatches:0,waiting_locks:0,longest_wait_seconds:0,duration_ms:2,rules:{}};
  if(args.p_action==='report')return {total:1,items:[{id:'p1',reference:'CAFE',name:'Café',method:'fifo',physical_quantity:5,book_quantity:5,value:50,provenance:'observed_opening'}],reconciliation:[]};
  if(args.p_action==='history')return {total:1,items:[{source:'Opening observed',kind:'opening',quantity:5,value_delta:50,expense_delta:0,value_after:50}]};
  if(args.p_action==='receipts')return {total:1,items:[{id:'receipt1',erp_reference:'REC-01',order_number:'PDC-01',name:'Café',quantity:10,remaining:5}]};
  return {id:'saved'};
 }}});
}
test('stock diagnostics use a single standard search and preserve the explanation workflow',async({page})=>{
 await boot(page);await page.evaluate(()=>ArchitectStockAudit.products());const d=page.locator('dialog').first();await expect(d.locator('tbody')).toContainText('CAFE');await expect(d.locator('input[type=search]')).toHaveCount(1);
 await d.locator('input[type=search]').fill('cafe');await expect.poll(()=>page.evaluate(()=>__auditCalls.at(-1).p_data.search)).toBe('cafe');
 await d.locator('[data-integrity-resolve]').click();const form=page.locator('dialog').last();await form.locator('[name=reason]').fill('Count INV-01, movement MOV-01 verified');await form.locator('[type=submit]').click();await expect(page.locator('dialog')).toHaveCount(1);
 expect(await page.evaluate(()=>__auditCalls.find(c=>c.p_action==='resolve').p_data)).toEqual({id:'case1',reason:'Count INV-01, movement MOV-01 verified'});
});
test('valuation configuration and history are explicit and searchable',async({page})=>{
 await boot(page);await page.evaluate(()=>ArchitectStockAudit.valuation());const d=page.locator('dialog').first();await expect(d.locator('[data-valuation-grid]')).toContainText('FIFO');await d.locator('[data-cost-config]').click();const form=page.locator('dialog').last();
 await form.locator('[name=method]').selectOption('avco');await form.locator('[name=opening_unit_cost]').fill('10');await form.locator('[name=reason]').fill('Finance approved method after empty stock');await form.locator('[type=submit]').click();await expect(page.locator('dialog')).toHaveCount(1);
 expect(await page.evaluate(()=>__auditCalls.find(c=>c.p_action==='configure').p_data)).toMatchObject({method:'avco',opening_unit_cost:'10',product_id:'p1'});
 await d.locator('[data-cost-history]').click();const history=page.locator('dialog').last();await expect(history.locator('tbody')).toContainText('Opening observed');await history.locator('input[type=search]').fill('Opening');await expect.poll(()=>page.evaluate(()=>__auditCalls.at(-1).p_data.search)).toBe('Opening');
});
test('a cost credit keeps selected receipt and stable request identity',async({page})=>{
 await boot(page);await page.evaluate(()=>ArchitectStockAudit.valuation());await page.locator('[data-landed]').click();const d=page.locator('dialog').last();await d.locator('[name=source_reference]').fill('CREDIT-2026-01');await d.locator('[name=amount]').fill('-15');await d.locator('[name=reason]').fill('Carrier credit for incorrect invoice');await d.locator('[data-receipt-id]').check();await expect(d.locator('[data-receipt-selection]')).toContainText('1');await d.locator('[type=submit]').click();await expect(page.locator('dialog')).toHaveCount(1);
 expect(await page.evaluate(()=>__auditCalls.find(c=>c.p_action==='landed').p_data)).toMatchObject({currency:'USD',amount:'-15',movement_ids:['receipt1'],source_reference:'CREDIT-2026-01'});
});
test('French audit controls remain usable on mobile and clear on logout',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(async()=>{await GamaI18n.setLanguage('fr');await ArchitectStockAudit.performance()});await expect(page.locator('dialog h2')).toHaveText('Contrôles techniques');await expect(page.locator('dialog')).toContainText('25');expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);await page.screenshot({path:'test-results/audit-mobile.png',fullPage:true});
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await expect(page.locator('dialog')).toHaveCount(0);
});
test('a late technical response cannot reopen financial controls after logout',async({page})=>{
 await boot(page);await page.evaluate(async()=>{await ArchitectStockAudit.products();document.querySelector('dialog').close()});
 await page.evaluate(()=>{window.ArcData={...ArcData,rpc:()=>new Promise(resolve=>window.__resolveAudit=resolve)};window.__auditPending=ArchitectStockAudit.performance()});
 await page.evaluate(async()=>{window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}}));__resolveAudit({rules:{}});await __auditPending});await expect(page.locator('dialog')).toHaveCount(0);
});
