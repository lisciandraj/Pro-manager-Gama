const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
async function boot(page){
 await page.addInitScript(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Admin'}));window.__DB={products:[],suppliers:[],customers:[],app_modules:[],company_settings:[{id:true,currency:'USD',country:'EC'}]};});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');await page.waitForFunction(()=>window.ArcRouter&&window.GamaCloud);
 await page.evaluate(async()=>{await ArcEnsureRuntime();await GamaCloudReady;window.__businessCalls=[];window.__contracts=[];window.__claims=[];window.__consultations=[];const old=GamaCloud.db;
  GamaCloud.db=async()=>{const client=await old();return {...client,rpc:async(name,args)=>{
   if(!['coco_contracts','coco_expenses','coco_consultations'].includes(name))return client.rpc(name,args);
   const a=args.p_action,d=args.p_data,now=new Date().toISOString().slice(0,10);__businessCalls.push({name,a,d});
   if(a==='lookups')return {data:[{id:d.kind==='products'?'product-1':'partner-1',name:d.kind==='products'?'Paper':'Partner',sale_price:10,address:'Quito'}]};
   if(a==='context')return {data:{today:now,currency:'USD',rights:{validate:true,pay:true},employees:[{id:'employee-1',name:'Ana'}],categories:[{id:'category-1',name:'Travel'}],vehicles:[],accounts:[{id:'bank-1',name:'Bank'}]}};
   const rows=name==='coco_contracts'?__contracts:name==='coco_expenses'?__claims:__consultations;
   if(a==='list')return {data:{today:now,total:rows.length,rows,occurrences:[]}};
   if(a==='save'){rows.push({...d,id:d.id||'claim-1',version:1,customer:'Partner',reference:'EXP-1',status:'draft',workflow:'draft',has_receipt:!!d.receipt});return {data:{id:rows.at(-1).id}};}
   if(a==='submit')return {error:{message:'RECEIPT_REQUIRED'}};
   if(a==='get')return {data:{...rows.find(x=>x.id===d.id),status:'open',currency:'USD',offers:[]}};
   return {data:{id:d.id}};
  }}};
 });
}
test('contracts load on demand and preserve data while adding a product in a nested form',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contracts'));await page.locator('#contracts [data-business-new]').click();let form=page.locator('dialog[open]').last();
 await form.locator('[name=name]').fill('Monthly paper');await form.locator('[name=customer_id]').selectOption('partner-1');await form.locator('[data-line-add]').click();
 const line=page.locator('dialog[open]').last();await line.locator('[name=product_id]').selectOption('product-1');await line.locator('[name=quantity]').fill('3');await line.locator('[type=submit]').click();
 await expect(page.locator('dialog[open]')).toHaveCount(1);form=page.locator('dialog[open]');await expect(form.locator('[name=name]')).toHaveValue('Monthly paper');await form.locator('[type=submit]').click();
 await expect(page.locator('#contracts')).toContainText('Monthly paper');const saved=await page.evaluate(()=>__businessCalls.find(x=>x.a==='save').d);expect(saved.lines[0].quantity).toBe(3);expect(saved.delivery_address).toBe('Quito');
});
test('expense receipts and employee selection are saved; submission errors remain inline',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('expenses'));await page.locator('#expenses [data-business-new]').click();const form=page.locator('dialog[open]');
 await form.locator('[name=description]').fill('Client visit');await form.locator('[name=category_id]').selectOption('category-1');await form.locator('[name=paid_by]').selectOption('employee');await form.locator('[name=employee_id]').selectOption('employee-1');await expect(form.locator('[name=financial_account_id]')).toBeDisabled();await form.locator('[name=amount_untaxed]').fill('20');
 await form.locator('[data-receipt]').setInputFiles({name:'receipt.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF-1.4 fixture')});await form.locator('[type=submit]').click();await expect(page.locator('#expenses')).toContainText('Client visit');
 const saved=await page.evaluate(()=>__businessCalls.find(x=>x.a==='save').d);expect(saved.receipt.filename).toBe('receipt.pdf');expect(saved.employee_id).toBe('employee-1');expect(saved.amount_total).toBe('20.00');
 await page.locator('[data-claim-action=submit]').click();await expect(page.locator('[data-business-error]')).toContainText('justificante');
});
test('supplier consultation forms fit a small viewport and retain product quantities',async({page})=>{
 await page.setViewportSize({width:375,height:812});await boot(page);await page.evaluate(()=>CocoBusiness.consultations());await page.locator('dialog [data-business-new]').click();let form=page.locator('dialog[open]').last();await form.locator('[name=name]').fill('Paper consultation');await form.locator('[data-line-add]').click();const line=page.locator('dialog[open]').last();await line.locator('[name=product_id]').selectOption('product-1');await line.locator('[name=quantity]').fill('12');await line.locator('[type=submit]').click();
 form=page.locator('dialog[open]').last();const bounds=await form.boundingBox();expect(bounds.width).toBeLessThanOrEqual(375);expect(bounds.x).toBeGreaterThanOrEqual(0);await form.locator('[type=submit]').click();await expect(page.locator('dialog[open]').last()).toContainText('Paper consultation');expect((await page.evaluate(()=>__businessCalls.find(x=>x.a==='save').d)).lines[0].quantity).toBe(12);
});

test('business list search stays beside its action without empty layout rows',async({page},info)=>{
 await boot(page);
 for(const id of ['contracts','expenses']){
  await page.evaluate(id=>ArcRouter.open(id),id);
  const host=page.locator('#'+id+' .cocoBusiness');await host.locator('[data-business-new]').waitFor();
  for(const width of [320,390,768,1024,1440,1920]){
   await page.setViewportSize({width,height:900});
   const search=host.locator('.arcToolbar [name=search]');await expect(search).toBeVisible();
   const input=await search.boundingBox(),button=await host.locator('[data-business-search]').boundingBox();
   expect(Math.abs(input.y+input.height-button.y-button.height)).toBeLessThanOrEqual(2);
   await expect(host.locator('[data-business-error]')).toBeHidden();
   expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(2);
   if(width<=768){
    const panel=page.locator('.cocoGlobalHistory .cocoFollowup');await expect(panel).toBeVisible();
    const history=await panel.boundingBox(),nav=await page.locator('.cocoMobileNav').boundingBox();
    expect(history.y+history.height).toBeLessThanOrEqual(nav.y-4);
    const reserve=await page.locator('.arcContent').evaluate(e=>parseFloat(getComputedStyle(e).paddingBottom));
    expect(reserve).toBeGreaterThanOrEqual(history.height+nav.height+16);
   }
   if(width===390||width===1440)await page.screenshot({path:info.outputPath(id+'-'+width+'.png')});
  }
  await host.locator('[name=search]').fill('Paper');await host.locator('[data-business-search]').click();
  await expect(host.locator('[name=search]')).toHaveValue('Paper');
 }
});
