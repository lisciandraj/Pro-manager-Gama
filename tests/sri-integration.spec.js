const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
const ID='00000000-0000-4000-8000-000000000001';
async function boot(page,options={}){
 await page.addInitScript(({ID,options})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:options.role||'admin',name:'SRI Test'}));
  window.__DB={products:[],customers:[],suppliers:[],profiles:[],app_modules:[],invoices:[],
   company_settings:[{id:true,currency:'USD',country:'EC'}],sri_settings:[{environment:'pruebas',estab:'001',pto_emi:'001',provider_ruc:'1790012345001'}],
   external_invoices:[{id:ID,number:'FAC-00000001',order_id:'order1',issue_date:'2026-09-27',created_at:'2026-09-27',total:115,subtotal:100,tax:15,document_kind:'internal',fiscal_status:'unverified',external_number:null,
    document_snapshot:{customer:'Cliente',customer_identification:'1712345678',quote_number:'COT-00000001',order_number:'PED-00000001',details:{},lines:[]}}],
   sri_invoice_issues:options.issue?[{id:ID,source_invoice_id:ID,environment:'pruebas',status:'processing',...options.issue}]:[]};
  window.__SRI={calls:[],runtime:{ready:false,provider:'openapi',can_refresh:true,can_export:true,...options.runtime}};
 },{ID,options});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');
 await page.waitForFunction(()=>window.GamaAccounting&&window.GamaCloud&&window.GamaCurrency);
 await page.evaluate(async()=>{
  await GamaCloudReady;const old=GamaCloud.db;
  GamaCloud.db=async()=>{const base=await old();return{...base,
   from(table){
    if(!['external_invoices','sri_invoice_issues'].includes(table))return base.from(table);
    let filters=[],range=[0,9999],orders=[];
    const q={select(){return q},eq(k,v){filters.push(r=>r[k]===v);return q},in(k,vs){filters.push(r=>vs.includes(r[k]));return q},
     ilike(k,value){filters.push(r=>String(r[k]||'').toLowerCase().includes(value.slice(1,-1).toLowerCase()));return q},
     order(k,opts){orders.push([k,opts]);return q},range(a,b){range=[a,b];return q},
     then(ok,fail){let rows=__DB[table].filter(r=>filters.every(fn=>fn(r)));for(const[k,o]of orders)rows.sort((a,b)=>String(a[k]).localeCompare(String(b[k]))*(o.ascending?1:-1));return Promise.resolve({count:rows.length,data:structuredClone(rows.slice(range[0],range[1]+1))}).then(ok,fail)}};
    return q;
   },
   rpc:async(fn,args)=>{
    if(fn==='gama_accounting_action'){
     __SRI.calls.push({fn,...args});
     return {data:{scope:'all',currency:'USD',rights:{view:true,create:true,edit:true,export:true,validate:true},revenue:{},expense:{},customers:{},suppliers:{},treasury:{accounts:[]},taxes:{},alerts:{}}};
    }
    if(fn==='gama_sri_prepare'){
     __SRI.calls.push({fn,...args});__DB.sri_invoice_issues.push({id:args.p_invoice_id,source_invoice_id:args.p_invoice_id,environment:'pruebas',status:'draft'});return{data:{id:args.p_invoice_id}};
    }
    return base.rpc(fn,args);
   },
   functions:{invoke:async(name,{body})=>{__SRI.calls.push({name,...body});return{data:body.action==='status'?__SRI.runtime:{status:'processing',review_required:true}}}}
  }};
 });
}

test('standalone SRI workspace loads lazily and does not trigger accounting synchronization',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaAccounting.openSri());
 await expect(page.locator('#sri')).toBeVisible();await expect(page.locator('#gaMain')).toContainText('Open API Facturación SRI');
 await expect(page.locator('[data-ga-sri="prepare"]')).toBeEnabled();
 expect(await page.evaluate(()=>__SRI.calls.some(c=>c.p_action==='sync'))).toBe(false);
 await page.locator('#gaSriPayment').selectOption('01');await page.locator('[data-ga-sri="prepare"]').click();
 await expect(page.locator('[data-ga-sri="submit"]')).toBeDisabled();
 expect(await page.evaluate(()=>__SRI.calls.find(c=>c.fn==='gama_sri_prepare'))).toMatchObject({p_invoice_id:ID,p_payment_code:'01'});
 expect(await page.evaluate(()=>__SRI.calls.some(c=>c.action==='submit'))).toBe(false);
});

test('uncertain Open API document offers lookup, never a reissue or reset',async({page})=>{
 await boot(page,{issue:{receipt:{provider:'openapi'},last_error:'SRI_OPENAPI_RECONCILIATION_REQUIRED'}});
 await page.evaluate(()=>GamaAccounting.openSri());
 await expect(page.locator('[data-ga-sri="refresh"]')).toBeEnabled();
 await expect(page.locator('[data-ga-sri="retry"]')).toHaveCount(0);
 await expect(page.locator('[data-ga-sri="submit"]')).toHaveCount(0);
 await page.locator('[data-ga-sri="refresh"]').click();
 await expect.poll(()=>page.evaluate(()=>__SRI.calls.filter(c=>c.action==='refresh').length)).toBe(1);
});

test('invoice links use the source identity; internal invoice opens the fiscal workspace',async({page})=>{
 await boot(page);
 await page.evaluate(async()=>{__DB.external_invoices.push({...__DB.external_invoices[0],id:'other',number:'OTHER'});await GamaInternalInvoices.view(__DB.external_invoices[0].id)});
 await expect(page.locator('#giSri')).toBeVisible();await page.locator('#giSri').click();
 await expect(page.locator('#sri')).toBeVisible();await expect(page.locator('#gaMain')).toContainText('FAC-00000001');
 await expect(page.locator('#gaMain')).not.toContainText('OTHER');
 await expect(page.locator('[data-ga-sri-pay]')).toHaveAttribute('data-ga-sri-pay',ID);
 await expect(page.locator('[data-ga-sri-flow]')).toHaveAttribute('data-ga-sri-flow','order1');
 await page.locator('#gaSriAll').click();await expect(page.locator('#gaMain')).toContainText('OTHER');
});

test('pagination loads the matching fiscal issue and escapes untrusted errors',async({page})=>{
 await boot(page);await page.evaluate(()=>{
  const base=__DB.external_invoices[0];__DB.external_invoices=Array.from({length:35},(_,n)=>({...base,id:String(n),number:'INV-'+n,created_at:String(n).padStart(3,'0')}));
  __DB.sri_invoice_issues=[{id:'fiscal',source_invoice_id:'0',status:'error',last_error:'<img src=x onerror="window.__XSS=1">'}];
  return GamaAccounting.openSri();
 });
 await expect(page.locator('#gaMain tbody tr')).toHaveCount(30);await page.locator('#gaSriNext').click();
 await expect(page.locator('#gaMain tbody tr')).toHaveCount(5);await expect(page.locator('#gaMain')).toContainText('<img');
 expect(await page.evaluate(()=>window.__XSS)).toBeUndefined();
 await page.locator('#gaSriSearch').fill('INV-34');await page.locator('#gaSriFind').click();
 await expect(page.locator('#gaMain tbody tr')).toHaveCount(1);await expect(page.locator('#gaMain')).toContainText('INV-34');
});

test('switching workspaces keeps finance IDs unique and removes fiscal data on logout',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaAccounting.openSri());await page.locator('#gaSriAccounting').click();
 await expect(page.locator('#accounting')).toBeVisible();await expect(page.locator('#gaMain')).toHaveCount(1);
 await page.evaluate(()=>GamaAccounting.openSri());await expect(page.locator('#gaMain')).toHaveCount(1);
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));
 await expect(page.locator('#gaMain')).toHaveCount(0);
});

test('commercial users cannot enter the SRI workspace',async({page})=>{
 await boot(page,{role:'commercial'});await page.evaluate(()=>GamaAccounting.openSri());
 await expect(page.locator('#sri')).toHaveCount(0);
 expect(await page.evaluate(()=>__SRI.calls.some(c=>c.action==='status'))).toBe(false);
});

test('mobile SRI uses the existing horizontal table container without overflowing the viewport',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(()=>GamaAccounting.openSri());
 await expect(page.locator('#sri')).toBeVisible();await expect(page.locator('#gaMain .gaScroll')).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth+2)).toBe(true);
});


test('payment details open the exact fiscal invoice without posting a payment',async({page})=>{
 await boot(page);await page.evaluate(async()=>{
  const old=GamaCloud.db;
  GamaCloud.db=async()=>{const c=await old();return {...c,rpc:async(fn,args)=>{
   if(fn==='gama_payment_action'){
    __SRI.calls.push({fn,...args});
    if(args.p_action!=='detail')throw Error('Unexpected payment mutation');
    return {data:{...__DB.external_invoices[0],customer_name:'Cliente',identification:'1712345678',customer_id:'c1',email:'',payment_status:'pending',paid:0,balance:115,lines:[],payments:[]}};
   }
   return c.rpc(fn,args);
  }}};
  await GamaPayments.open({invoiceId:__DB.external_invoices[0].id});
 });
 await expect(page.locator('#gpSri')).toBeVisible();await page.locator('#gpSri').click();
 await expect(page.locator('#sri')).toBeVisible();await expect(page.locator('#gaMain')).toContainText('FAC-00000001');
 expect(await page.evaluate(()=>__SRI.calls.some(c=>c.fn==='gama_payment_action'&&c.p_action!=='detail'))).toBe(false);
});
