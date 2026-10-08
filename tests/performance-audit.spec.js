const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
async function boot(page){
 await page.addInitScript(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({userId:'test-admin-uid',role:'admin',name:'QA'}));window.__DB={products:Array.from({length:1836},(_,i)=>({id:'p'+i,barcode:'B'+i,name:'Product '+String(i).padStart(4,'0'),description:'Description '.repeat(15),stock:20,min_stock:1,sale_price:4,tax_rate:15,active:true})),customers:[{id:'c1',name:'Customer',active:true}],suppliers:[],invoices:[],invoice_lines:[]}});
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;(()=>{const list=GamaCloud.list;window.__perfReads=[];GamaCloud.list=async(table,options={})=>{const r=await list(table,options);__perfReads.push({table,options,rows:r.data?.length||0,bytes:JSON.stringify(r.data||[]).length});return r}})();`}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.ArcRuntimeLoaded&&window.gamaAccessAllowed?.('products'));await page.addScriptTag({url:'/gama-invoice-archive.js'});
}
test('home and product directory avoid hidden archive and full catalogue reads',async({page})=>{
 await boot(page);await page.waitForTimeout(700);
 const home=await page.evaluate(()=>__perfReads.filter(r=>['products','customers','invoices','invoice_lines'].includes(r.table)));
 await page.evaluate(()=>{__perfReads=[];ArcRouter.show('products')});await expect(page.locator('#productsTable [data-arc-directory] tbody tr')).toHaveCount(20);await page.waitForTimeout(500);
 const products=await page.evaluate(()=>__perfReads.filter(r=>r.table==='products'));
 console.log('AUDIT_READS '+JSON.stringify({home:{requests:home.length,rows:home.reduce((n,r)=>n+r.rows,0),bytes:home.reduce((n,r)=>n+r.bytes,0)},products:{requests:products.length,rows:products.reduce((n,r)=>n+r.rows,0),bytes:products.reduce((n,r)=>n+r.bytes,0)}}));
 if(!process.env.AUDIT_BASELINE){expect(home).toEqual([]);expect(products.filter(r=>!r.options.head).reduce((n,r)=>n+r.rows,0)).toBeLessThanOrEqual(20)}
});

test('global search is absent from startup and opens through its lazy entry point',async({page})=>{
 await boot(page);
 expect(await page.evaluate(()=>performance.getEntriesByType('resource').some(r=>/gama-global-search(?:-core)?\.js/.test(r.name)))).toBe(false);
 await page.locator('#arcSearchInput').click();await expect(page.locator('#gamaSpotlight')).toBeVisible();
 await page.keyboard.press('Escape');await page.keyboard.press('Control+k');await expect(page.locator('#gamaSpotlight')).toBeVisible();
 expect(await page.evaluate(()=>performance.getEntriesByType('resource').filter(r=>/gama-global-search-core\.js/.test(r.name)).length)).toBe(1);
});
test('notification badge coalesces concurrent refreshes into a lightweight request',async({page})=>{
 await boot(page);
 await page.evaluate(async()=>{const real=GamaCloud.db;const client=await real();window.__badgeCalls=[];GamaCloud.db=async()=>({...client,rpc:async(name,args)=>{if(name==='gama_operations_action'){__badgeCalls.push(args);await new Promise(r=>setTimeout(r,50));return {data:{active_count:2}}}return client.rpc(name,args)}});await Promise.all([GamaOperations.refreshBadge(),GamaOperations.refreshBadge(),GamaOperations.refreshBadge()])});
 expect(await page.evaluate(()=>__badgeCalls)).toEqual([{p_action:'badge',p_data:{respect_preferences:true}}]);
});
test('hidden archive and hidden product directory ignore bursts of data changes',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.show('products'));await expect(page.locator('#productsTable [data-arc-directory] tbody tr')).toHaveCount(20);await page.evaluate(()=>{ArcRouter.show('home');__perfReads=[];for(let i=0;i<20;i++)dispatchEvent(new CustomEvent('gama:data-change',{detail:{table:'products'}}))});await page.waitForTimeout(600);
 expect(await page.evaluate(()=>__perfReads.filter(r=>['products','invoices','invoice_lines'].includes(r.table)))).toEqual([]);
});
