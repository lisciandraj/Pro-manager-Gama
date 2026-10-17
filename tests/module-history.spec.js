const {test,expect}=require('@playwright/test');
const {boot}=require('./order-followup-fixture.cjs');
async function setup(page,{proposal=false,module='products'}={}){
 await boot(page);await page.evaluate(({proposal,module})=>{
  window.__moduleNotes=[];window.__moduleDecisions=[];window.__moduleCalls=[];
  window.__moduleProposal=proposal?{id:'module-proposal',module_id:module,status:'pending',action:module==='contacts'?'contact_draft':'absence_request',summary:'Informations extraites du mail.',source_email:'new@example.invalid',source_label:'Signature du mail',payload:module==='contacts'?{first_name:'Marie',last_name:'Dubois',email:'new@example.invalid',company:'Entreprise inconnue'}:{employee_id:'employee',kind:'enfermedad',start_date:'2026-11-02',end_date:'2026-11-03'}}:null;
  const original=window.GamaCloud.db;window.GamaCloud.db=async()=>{const c=await original();return {...c,rpc:async(name,args)=>{
   if(name!=='coco_module_history')return c.rpc(name,args);window.__moduleCalls.push(args);const id=args.p_data.module_id;
   const context={kind:'module',module_id:id,number:window.ArcModules.get(id)?.label||id,status:'recorded',actor_id:'alice',can_note:true,can_review:true,stages:[]};
   if(args.p_action==='context')return {data:context};
   if(args.p_action==='proposal_options')return {data:{employees:[{id:'employee',label:'Employé Test'}],customers:[],leads:[]}};
   if(args.p_action==='review_proposal'){window.__moduleReviewed=args.p_data.payload;return {data:{hash:'module-check',review:{details:[args.p_data.payload.first_name||'Employé Test',args.p_data.payload.email||'2026-11-02 → 2026-11-03','À valider']}}}}
   if(args.p_action==='approve_proposal'){window.__moduleDecisions.push(args.p_data);window.__moduleProposal.status='approved';window.__moduleProposal.result={module:id,id:'created-record'};return {data:window.__moduleProposal.result}}
   if(args.p_action==='reject_proposal'){window.__moduleProposal.status='rejected';return {data:{status:'rejected'}}}
   if(args.p_action==='note'){window.__moduleNotes.push(args.p_data);return {data:{id:'note-1'}}}
   return {data:{context,history:window.__moduleHistory||[{id:'group-1',at:'2026-10-17T14:00:00Z',type:'action',action:'insert',subject:'Producto',actor_id:'alice',actor_name:'Alice',action_count:12,references:Array.from({length:12},(_,i)=>({kind:'product',id:'p'+i,reference:'REF-'+i,name:'Produit '+i,quantity:1})),links:[{module:'contacts',action:'module'},{module:'hr',action:'module'},{module:'evil-site',action:'module'}],source_type:'file',source_label:'Extrait de compte.pdf',total:1},...(window.__moduleProposal?[{id:'proposal-event',at:'2026-10-17T14:01:00Z',type:'proposal',action:'proposal',subject:'mail_analysis',actor_name:'Agent Coco',proposal_id:'module-proposal',body:window.__moduleProposal.summary,links:[]}]:[])],entries:window.__moduleNotes.map((n,i)=>({id:'note-'+i,type:'note',actor_id:'alice',actor_name:'Alice',body:n.body,created_at:'2026-10-17T14:02:00Z'})),proposals:window.__moduleProposal?[window.__moduleProposal]:[],portraits:{}}};
  }}};
 },{proposal,module});
 await page.evaluate(id=>window.ArcRouter.open(id),module);await expect(page.locator('.cocoGlobalHistory .cocoFollowupParty')).toBeAttached();
}
test('all-module sidebar groups references, shows sources, keeps authorized internal links and preserves business DOM',async({page})=>{
 await page.setViewportSize({width:1440,height:1000});await setup(page);const history=page.locator('.cocoGlobalHistory');await expect(history.locator('.cocoFollowupTitle')).toHaveText('Historique du module');await expect(history.locator('.cocoFollowupCount')).toHaveText('12 actions');await expect(history).toContainText('Extrait de compte.pdf');await expect(history.locator('.cocoFollowupReferences li:visible')).toHaveCount(5);await history.locator('.cocoFollowupReferences summary').click();await expect(history.locator('.cocoFollowupReferences li:visible')).toHaveCount(12);await expect(history.locator('.cocoFollowupLinks')).toContainText('Contacts');await expect(history).not.toContainText('evil-site');
 const main=await page.locator('#products').boundingBox(),side=await history.boundingBox();expect(side.x).toBeGreaterThanOrEqual(main.x+main.width);await page.screenshot({path:'test-results/followup-modules-desktop.png',fullPage:true});
});
test('a module note stays separate from grouped actions',async({page})=>{
 await setup(page);await page.locator('[data-compose-note]').click();await page.locator('.cocoFollowupForm textarea').fill('Import terminé depuis ChatGPT.');await page.locator('.cocoFollowupForm [type=submit]').click();await expect(page.locator('.cocoFollowupTimeline')).toContainText('Import terminé depuis ChatGPT.');expect((await page.evaluate(()=>window.__moduleNotes[0])).module_id).toBe('products');
});
test('contact fields are prefilled, editable and checked before creation',async({page})=>{
 await setup(page,{module:'contacts',proposal:true});await page.locator('[data-review-proposal]').click();const dialog=page.locator('.cocoModuleProposal');await expect(dialog.locator('[name=first_name]')).toHaveValue('Marie');await expect(dialog.locator('[type=submit]')).toBeDisabled();await dialog.locator('[name=phone]').fill('+32 123 456');await dialog.locator('[data-check]').click();await expect(dialog.locator('[data-preview]')).toContainText('Marie');await expect(dialog.locator('[type=submit]')).toBeEnabled();await dialog.locator('[name=first_name]').fill('Maria');await expect(dialog.locator('[type=submit]')).toBeDisabled();await dialog.locator('[data-check]').click();await dialog.locator('[type=submit]').click();await expect(dialog).toHaveCount(0);expect(await page.evaluate(()=>window.__moduleDecisions.length)).toBe(1);expect(await page.evaluate(()=>window.__moduleReviewed.first_name)).toBe('Maria');await expect(page.locator('[data-open-proposal]')).toBeVisible();
});
test('HR proposal explains the pending decision and refusal creates no record',async({page})=>{
 await setup(page,{module:'hr',proposal:true});await page.locator('[data-review-proposal]').click();const dialog=page.locator('.cocoModuleProposal');await expect(dialog.locator('[name=employee_id]')).toHaveValue('employee');await expect(dialog).toContainText('en attente de décision RH');await dialog.locator('[data-close]').last().click();await page.locator('[data-reject-proposal]').click();await expect(page.locator('.cocoProposalState')).toHaveText('Refusé');expect(await page.evaluate(()=>window.__moduleDecisions.length)).toBe(0);
});
test('phone panel stays in the viewport; navigation removes the previous module history',async({page})=>{
 await page.setViewportSize({width:390,height:844});await setup(page);await page.locator('.cocoGlobalHistory .cocoFollowup>summary').click();await expect(page.locator('.cocoGlobalHistory .cocoFollowupTimeline')).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);await page.screenshot({path:'test-results/followup-modules-phone.png',fullPage:true});await page.evaluate(()=>window.ArcRouter.open('quotes'));await expect(page.locator('.cocoGlobalHistory')).toHaveCount(0);await expect(page.locator('.cocoFollowup')).toHaveCount(1);
});
test('settings modules expose the shared history inside their dialog',async({page})=>{
 await setup(page);await page.evaluate(()=>window.GamaSettings.open('reports'));await expect(page.locator('#arcSettingsDialog .cocoSettingsHistory')).toBeVisible();await expect(page.locator('#arcSettingsDialog .cocoFollowupParty')).toContainText('Importer');await page.locator('#arcSettingsDialog').evaluate(d=>d.close());await expect(page.locator('.cocoGlobalHistory')).toHaveCount(1);
});
test('sign-out disposes the global panel and review dialog',async({page})=>{
 await setup(page,{module:'contacts',proposal:true});await page.locator('[data-review-proposal]').click();await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await expect(page.locator('.cocoGlobalHistory,.cocoModuleProposal')).toHaveCount(0);
});
