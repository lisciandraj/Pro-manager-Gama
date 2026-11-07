const {test,expect}=require('@playwright/test');
const path=require('node:path');
test.use({serviceWorkers:'block'});
async function boot(page,{isNew=false,request=false}={}){
 await page.route('**/*',route=>new URL(route.request().url()).hostname==='127.0.0.1'?route.continue():route.abort());
 await page.route('**/quote-autosave-fixture.html',route=>route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es"><head><style>svg{width:20px;height:20px}input,select,button{min-height:30px}label{display:block}</style></head><body><section id="mainmenu" hidden>Menu</section><section id="quotes" class="active"><div id="quotes-main"></div></section></body></html>'}));
 await page.goto('/quote-autosave-fixture.html');
 await page.evaluate(async()=>{
  const [ui,icons,format]=await Promise.all([import('/src/ui/components.js'),import('/src/ui/icons.js'),import('/src/domain/format.js')]);window.ArcUI={...ui,...icons,esc:format.escapeHtml};window.GamaI18n={language:'es',t:s=>s};window.ArcFormat=format.format;
  window.gamaAccessAllowed=id=>id==='quotes';window.GamaCompany={load:async()=>{},get:()=>({timezone:'UTC'}),defaultsForQuote:()=>({seller:'QA'})};window.ArcEntities={formatAddress:row=>row.address||''};window.CocoPlanning={quoteMargin:()=>{}};
  window.__epoch=0;window.__calls=[];window.__requestCalls=[];window.__views=[];window.__changes=0;window.__server={id:'q1',revision:1};window.addEventListener('gama:sales-change',()=>__changes++);
  window.CocoSalesWorkspace={attachSearch:()=>{},lookup:async kind=>kind==='customers'?[{id:'c1',name:'Andes',identification:'RUC',address:'Quito',active:true}]:[{id:'p1',name:'Papel',reference:'PAPEL',base_unit:'Unidad',active:true,tax_rate:15}],rpc:async()=>[]};
  window.ArcLoadScript=async()=>{};window.CocoModuleHistory={open:()=>{}};window.ArcRouter=(await import('/src/app/router.js')).router;ArcRouter.show('quotes');
  window.__context={rows:async()=>[],rpc:async(name,args)=>{if(name==='gama_quote_from_request'){__requestCalls.push(args);return window.__requestResult||{id:'request-q',revision:1,state:'draft',request_id:args.p_request_id,existing:false};}return [];},action:async(action,payload)=>{
   __calls.push(structuredClone(payload));if(window.__hold)await new Promise(resolve=>window.__release=resolve);if(window.__fail)throw Error(__fail);
   // The server receipt returns its original revision on an identical create retry.
   if(!payload.id&&window.__createReceipt){if(JSON.stringify(__createReceipt.payload)!==JSON.stringify(payload))throw Error('REQUEST_KEY_REUSED');return structuredClone(__createReceipt.result);}
   if(payload.id&&payload.revision!==__server.revision)throw Error('QUOTE_CHANGED');if(!payload.id)__server.id='created-q';__server.revision++;const result=window.__saveResult||{...__server};
   if(!payload.id){window.__createReceipt={payload:structuredClone(payload),result:structuredClone(result)};if(window.__loseSaveResponse){window.__loseSaveResponse=false;throw Error('response lost after commit');}}return result;
  },run:async(button,fn)=>{button.disabled=true;try{await fn();}catch(error){document.getElementById('gqMessage').textContent=error.message;}finally{button.disabled=false;}},fail:(host,error)=>{throw error;},view:async id=>__views.push(id),open:()=>__views.push('list'),openRequests:()=>__views.push('requests'),getAddressEpoch:()=>__epoch};
 });
 await page.addScriptTag({path:path.join(__dirname,'../src/features/sales/editor.js')});
 await page.evaluate(async({isNew,request})=>{
  const quote={...(isNew?{}:{id:'q1',quote_revision:1}),customer_id:'c1',invoice_number:isNew?'':'COT-1',issue_date:'2026-11-01',quote_valid_until:'2026-12-01',quote_details:{seller:'QA',client:'Andes',delivery_address:'Quito'},lines:[{product_id:'p1',quantity:1,quote_description:'Papel',quote_list_price:10,quote_discount:0,tax_rate:15}]};
  await CocoSalesEditor.quote(quote,request?{id:'r1'}:null,__context);
 },{isNew,request});
 await expect(page.locator('#gqAutosave')).toBeVisible();
}

test('automatically saves a changed draft, keeps editing and uses the returned revision for the next save',async({page})=>{
 await boot(page);await page.locator('#gqd_notes').fill('Première note');await expect.poll(()=>page.evaluate(()=>__calls.length)).toBe(1);
 await expect(page.locator('#gqForm')).toBeVisible();await expect(page.locator('#gqAutosave')).toHaveText('Borrador guardado.');
 await page.evaluate(()=>{__epoch++;window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'USER_UPDATED'}}));});
 await page.locator('#gqd_notes').fill('Deuxième note');await expect.poll(()=>page.evaluate(()=>__calls.length)).toBe(2);
 expect(await page.evaluate(()=>__calls.map(call=>({id:call.id,revision:call.revision,notes:call.details.notes})))).toEqual([{id:'q1',revision:1,notes:'Première note'},{id:'q1',revision:2,notes:'Deuxième note'}]);
 await page.locator('#gqSave').click();await expect.poll(()=>page.evaluate(()=>__views)).toEqual(['q1']);expect(await page.evaluate(()=>__calls.length)).toBe(2);
});

test('new valid drafts are created once and edits made while saving are sent as the next revision',async({page})=>{
 await boot(page,{isNew:true});await page.evaluate(()=>__hold=true);await expect.poll(()=>page.evaluate(()=>__calls.length)).toBe(1);
 await page.locator('#gqd_notes').fill('Écrit pendant la sauvegarde');await expect(page.locator('#gqSave')).toBeDisabled();
 await page.evaluate(()=>{__hold=false;__release();});await expect.poll(()=>page.evaluate(()=>__calls.length)).toBe(2);
 expect(await page.evaluate(()=>__calls[1])).toMatchObject({id:'created-q',revision:2,details:{notes:'Écrit pendant la sauvegarde'}});
 expect(await page.evaluate(()=>new Set(__calls.map(call=>call.request_key)).size)).toBe(1);
});

test('a lost creation response can be retried with the same request key and the original revision',async({page})=>{
 await boot(page,{isNew:true});await page.evaluate(()=>window.__loseSaveResponse=true);await page.locator('#gqSave').click();await expect(page.locator('#gqMessage')).toHaveText('response lost after commit');await expect(page.locator('#gqForm')).toBeVisible();
 await page.locator('#gqSave').click();await expect.poll(()=>page.evaluate(()=>__views)).toEqual(['created-q']);
 expect(await page.evaluate(()=>__calls.length)).toBe(2);expect(await page.evaluate(()=>__calls[0])).toEqual(await page.evaluate(()=>__calls[1]));expect(await page.evaluate(()=>__server.revision)).toBe(2);expect(await page.evaluate(()=>__changes)).toBe(1);
});

test('a conflict pauses automatic saves, retains typed values and asks before abandoning changes',async({page})=>{
 await boot(page);await page.evaluate(()=>__fail='QUOTE_CHANGED');await page.locator('#gqd_notes').fill('À conserver');await expect.poll(()=>page.evaluate(()=>__calls.length)).toBe(1);
 await expect(page.locator('#gqAutosave')).toContainText('no se ha guardado');await page.locator('#gqd_notes').fill('Toujours à conserver');
 await page.waitForTimeout(2200);expect(await page.evaluate(()=>__calls.length)).toBe(1);await expect(page.locator('#gqd_notes')).toHaveValue('Toujours à conserver');
 page.once('dialog',dialog=>dialog.dismiss());await page.locator('#gqDiscard').click();expect(await page.evaluate(()=>__views.length)).toBe(0);
 await page.evaluate(()=>__fail=null);await page.locator('#gqSave').click();await expect.poll(()=>page.evaluate(()=>__views)).toEqual(['q1']);
});

test('incomplete drafts do not autosave or steal focus and remain protected against reload',async({page})=>{
 await boot(page);await page.locator('[data-k=quantity]').fill('');await page.locator('#gqd_notes').focus();await page.waitForTimeout(2200);
 expect(await page.evaluate(()=>__calls.length)).toBe(0);await expect(page.locator('#gqd_notes')).toBeFocused();
 expect(await page.evaluate(()=>{const event=new Event('beforeunload',{cancelable:true});window.dispatchEvent(event);return event.defaultPrevented;})).toBe(true);
});

test('customer requests keep explicit conversion and a late response after logout cannot update the new session',async({page})=>{
 await boot(page,{request:true});await page.locator('#gqd_notes').fill('Demande');await page.waitForTimeout(2200);expect(await page.evaluate(()=>__requestCalls.length)).toBe(0);await page.locator('#gqSave').click();await expect.poll(()=>page.evaluate(()=>__requestCalls.length)).toBe(1);
 await boot(page);await page.evaluate(()=>__hold=true);await page.locator('#gqd_notes').fill('Ancienne session');await expect.poll(()=>page.evaluate(()=>__calls.length)).toBe(1);
 await page.evaluate(()=>{__epoch++;window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}}));__hold=false;__release();});
 await page.waitForTimeout(100);expect(await page.evaluate(()=>__changes)).toBe(0);expect(await page.evaluate(()=>__views)).toEqual([]);
});

for(const result of [{id:'q1'},{id:'q1',existing:true},{id:'q1',existing:'true'}])test('normal quote saves reject missing revisions '+JSON.stringify(result),async({page})=>{
 await boot(page);await page.evaluate(result=>window.__saveResult=result,result);await page.locator('#gqd_notes').fill('Conservar los cambios');await page.locator('#gqSave').click();
 await expect(page.locator('#gqMessage')).toHaveText('INVALID_SAVE_RESPONSE');await expect(page.locator('#gqAutosave')).toContainText('no se ha guardado');await expect(page.locator('#gqd_notes')).toHaveValue('Conservar los cambios');expect(await page.evaluate(()=>__views)).toEqual([]);expect(await page.evaluate(()=>__changes)).toBe(0);
});

test('programmatic and global-search route requests warn before destroying an incomplete editor',async({page})=>{
 await boot(page);await page.locator('[data-k=quantity]').fill('');let confirmations=0;
 page.once('dialog',async dialog=>{confirmations++;await dialog.dismiss();});
 expect(await page.evaluate(()=>ArcRouter.navigate('mainmenu',()=>{window.__navigated=true;return ArcRouter.show('mainmenu');}))).toBe(false);expect(await page.evaluate(()=>!!window.__navigated)).toBe(false);await expect(page.locator('#gqForm')).toBeVisible();await expect(page.locator('[data-k=quantity]')).toHaveValue('');
 page.once('dialog',async dialog=>{confirmations++;await dialog.accept();});
 expect(await page.evaluate(()=>ArcRouter.open('mainmenu'))).toBe(true);await expect(page.locator('#mainmenu')).toBeVisible();expect(confirmations).toBe(2);
});

test('forced logout cannot be prevented by the unsaved-draft guard',async({page})=>{
 await boot(page);await page.locator('[data-k=quantity]').fill('');let confirmations=0;page.on('dialog',async dialog=>{confirmations++;await dialog.dismiss();});
 await page.evaluate(async()=>{const router=await import('/src/app/router.js');router.startRouter();window.gamaAccessAllowed=()=>false;window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}}));});
 await expect(page.locator('#mainmenu')).toBeVisible();expect(confirmations).toBe(0);
});
