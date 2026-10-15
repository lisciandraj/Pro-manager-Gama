const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');

async function boot(page){
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'UX QA'}));
  localStorage.setItem('gama_tms_migrated_v1','1');
  window.__DB={products:[],suppliers:[],customers:[],sales_orders:[],sales_order_lines:[],invoice_lines:[],external_invoices:[],invoices:Array.from({length:35},(_,i)=>({id:'q'+i,invoice_number:'UX-'+i,quote_state:'draft',quote_revision:1,issue_date:'2026-10-01',quote_valid_until:'2026-11-01',quote_details:{seller:'QA',client:'Cliente de prueba',delivery_address:'Quito'},total:100+i}))};
 });
 // Both local configurations (HTTP and HTTPS) must remain reachable.
 // Every non-local request stays blocked; business reads use the fixture below.
 await page.route('**/*',r=>['127.0.0.1','localhost','[::1]'].includes(new URL(r.request().url()).hostname)?r.continue():r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.gamaAccessAllowed?.('quotes'));
 await page.evaluate(async()=>{
  const old=GamaCloud.db;window.__queueCalls=[];
  GamaCloud.db=async()=>{const db=await old();return {...db,rpc:async(fn,args)=>{
   if(fn==='gama_sales_workspace'&&args.p_action==='queue'){
    const d=args.p_data;__queueCalls.push(d);
    const all=__DB.invoices.filter(q=>!d.search||q.invoice_number.includes(d.search));
    return {data:{total:all.length,rows:all.slice(d.offset,d.offset+30).map(q=>({id:q.id,kind:'quote',number:q.invoice_number,customer_name:q.quote_details.client,status:'draft',next_action:'review'}))}};
   }
   return db.rpc(fn,args);
  }}};
  await GamaQuotes.open();
 });
}

test('return from a quote restores the work queue, filters, page, scroll and keyboard focus',async({page})=>{
 await page.setViewportSize({width:1440,height:700});await boot(page);
 await page.locator('[data-sales-queue]').click();
 await page.locator('#cocoQueueSearch').fill('UX-');await page.locator('#cocoQueueFind').click();
 await page.locator('#cocoQueueKind').selectOption('quote');
 await expect.poll(()=>page.evaluate(()=>__queueCalls.at(-1).kind)).toBe('quote');
 await page.locator('#cocoQueueNext').click();await expect(page.locator('[data-coco-open]')).toHaveCount(5);
 const row=page.locator('[data-coco-open=q34]');await row.scrollIntoViewIfNeeded();
 const top=await page.evaluate(()=>scrollY);await row.click();await expect(page.locator('#gqBack')).toBeVisible();
 await page.locator('#gqBack').click();await expect(page.locator('[data-coco-open=q34]')).toBeFocused();
 await expect(page.locator('#cocoQueueSearch')).toHaveValue('UX-');await expect(page.locator('#cocoQueueKind')).toHaveValue('quote');
 await expect(page.locator('[data-coco-open]')).toHaveCount(5);
 expect(await page.evaluate(()=>__queueCalls.at(-1))).toMatchObject({offset:30,search:'UX-',kind:'quote'});
 expect(Math.abs(await page.evaluate(()=>scrollY)-top)).toBeLessThanOrEqual(2);
 await page.locator('[data-coco-sales-section=documents]').click();
 await page.locator('[data-sales-queue]').click();await expect(page.locator('[data-coco-open]')).toHaveCount(5);
 await page.evaluate(()=>{__DB.invoices.splice(2);return CocoSalesWorkspace.open('queue')});
 await expect(page.locator('[data-coco-open]')).toHaveCount(2);
 expect(await page.evaluate(()=>__queueCalls.at(-1).offset)).toBe(0);
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));
 await page.evaluate(()=>CocoSalesWorkspace.open('queue'));
 await expect(page.locator('#cocoQueueSearch')).toHaveValue('');
 expect(await page.evaluate(()=>__queueCalls.at(-1))).toMatchObject({offset:0,search:'',kind:'all'});
});

test('quote cards and explicit table preference remain usable in every language and target width',async({page},info)=>{
 await boot(page);
 for(const language of ['fr','es','en']){
  await page.evaluate(lang=>GamaI18n.setLanguage(lang),language);
  for(const width of [360,390,768,1440]){
   await page.setViewportSize({width,height:900});
   await expect(page.locator('#gqList')).toHaveAttribute('data-gama-view',width<=760?'cards':'table');
   expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),language+' '+width).toBe(true);
   await expect(page.locator('#gqSearch')).toBeVisible();
   if(width<=760){
    const button=page.locator('[data-gq-open]').first(),box=await button.boundingBox();
    expect(box.width).toBeGreaterThan(150);expect(box.height).toBeGreaterThanOrEqual(44);
    const labels=await page.locator('#gqList tbody tr').first().evaluate(row=>[...row.cells].filter(c=>c.dataset.col&&!c.hasAttribute('data-gama-title')).map(c=>getComputedStyle(c,'::before').content));
    expect(labels.length).toBeGreaterThanOrEqual(3);expect(labels.every(x=>x!=='none'&&x!=='""')).toBe(true);
   }else expect(await page.locator('#gqList td.arcNumeric').first().evaluate(e=>getComputedStyle(e).textAlign)).toBe('right');
  }
 }
 await page.setViewportSize({width:390,height:900});await page.locator('[data-table-view=table]').click();
 await page.locator('#gqRefresh').click();await expect(page.locator('#gqList')).toHaveAttribute('data-gama-view','table');
 await page.locator('[data-table-view=cards]').click();await page.evaluate(()=>GamaI18n.setLanguage('fr'));
 await page.screenshot({path:info.outputPath('sales-mobile.png')});
});

test('shared field validation is translated, preserves help and values, and retains retry behavior',async({page})=>{
 await boot(page);
 for(const [lang,required] of [['fr','Complétez ce champ.'],['es','Completa este campo.'],['en','Complete this field.']]){
  await page.evaluate(async language=>{
   await GamaI18n.setLanguage(language);window.__formSaves=0;
   ArcUI.dialog({title:'Contacto',body:ArcUI.field({id:'ux-email',label:'Email',type:'email',required:true,help:'Email'})+ArcUI.field({id:'ux-quantity',label:'Cantidad',type:'number',required:true,min:1,value:2}),saveLabel:'Guardar',onSave:()=>{__formSaves++;if(__formSaves===1)throw Error('NETWORK_TEST')}});
  },lang);
  const submit=page.locator('dialog [type=submit]');await submit.click();
  await expect(page.locator('#ux-email')).toBeFocused();await expect(page.locator('#ux-email-error')).toHaveText(required);
  await expect(page.locator('#ux-email')).toHaveAttribute('aria-describedby','ux-email-help ux-email-error');
  expect(await page.evaluate(()=>__formSaves)).toBe(0);
  await page.locator('#ux-email').fill('person@example.invalid');await expect(page.locator('#ux-email-error')).toBeHidden();
  await expect(page.locator('#ux-email')).toHaveAttribute('aria-describedby','ux-email-help');
  await submit.click();await expect(page.locator('dialog [role=alert]')).toContainText('NETWORK_TEST');
  await expect(page.locator('#ux-email')).toHaveValue('person@example.invalid');await expect(page.locator('#ux-quantity')).toHaveValue('2');
  await submit.click();await expect(page.locator('dialog')).toHaveCount(0);expect(await page.evaluate(()=>__formSaves)).toBe(2);
 }
});

test('quote primary action and status remain readable with a visible keyboard focus',async({page})=>{
 await boot(page);await page.locator('#gqNew').focus();await page.keyboard.press('Tab');await page.keyboard.press('Shift+Tab');
 await expect(page.locator('#gqNew')).toBeFocused();
 const measures=await page.evaluate(()=>{
  const luminance=c=>{const v=c.match(/[\d.]+/g).slice(0,3).map(Number).map(x=>{x/=255;return x<=.04045?x/12.92:((x+.055)/1.055)**2.4});return .2126*v[0]+.7152*v[1]+.0722*v[2]};
  const contrast=e=>{const s=getComputedStyle(e),a=luminance(s.color),b=luminance(s.backgroundColor);return (Math.max(a,b)+.05)/(Math.min(a,b)+.05)};
  const action=document.getElementById('gqNew'),s=getComputedStyle(action);
  return {action:contrast(action),status:contrast(document.querySelector('#gqList .gqBadge')),focus:action.matches(':focus-visible'),outline:parseFloat(s.outlineWidth)};
 });
 expect(measures.action).toBeGreaterThanOrEqual(4.5);expect(measures.status).toBeGreaterThanOrEqual(4.5);
 expect(measures.focus).toBe(true);expect(measures.outline).toBeGreaterThanOrEqual(2);
});
