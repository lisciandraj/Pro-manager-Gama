const {test,expect}=require('@playwright/test');
const {boot}=require('./order-followup-fixture.cjs');
async function setup(page,{proposal=false,module='products'}={}){
 await boot(page);await page.evaluate(({proposal,module})=>{
  window.__moduleNotes=[];window.__moduleDecisions=[];window.__moduleCalls=[];
  window.__moduleProposal=proposal?{id:'module-proposal',module_id:module,can_review:true,status:'pending',action:module==='contacts'?'contact_draft':'absence_request',summary:'Informations extraites du mail.',source_email:'new@example.invalid',source_label:'Signature du mail',payload:module==='contacts'?{first_name:'Marie',last_name:'Dubois',email:'new@example.invalid',company:'Entreprise inconnue'}:{employee_id:'employee',kind:'enfermedad',start_date:'2026-11-02',end_date:'2026-11-03'}}:null;
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
test('the existing dossier panel shows the origin of an action requested in ChatGPT',async({page})=>{
 await boot(page);await page.evaluate(()=>{window.__history=[{id:'source-annotation',module_id:'sales-orders',at:'2026-10-17T14:01:00Z',type:'action',action:'source_linked',subject:'Origen de la acción',body:'Action demandée depuis ChatGPT.',actor_id:'alice',actor_name:'Alice',source_type:'chat',source_id:'real-chat-source',source_label:'Demande ChatGPT',links:[{module:'contacts',action:'module'}],total:1}]});await page.locator('[data-refresh]').click();await expect(page.locator('.cocoFollowupEventTitle')).toHaveText('Origine de l’action');await expect(page.locator('.cocoFollowupTimeline')).toContainText('Demande ChatGPT');await expect(page.locator('.cocoFollowupLinks')).toContainText('Contacts');
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

for(const width of [390,1440])test(`audit entries keep translated labels, safe references and filters at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});await setup(page);await page.evaluate(()=>{
  window.__moduleHistory=[{id:'audit-1',module_id:'products',source_type:'audit',at:'2026-10-18T12:00:00Z',type:'action',action:'receipt',subject:'Recepción de compra',actor_id:'alice',actor_name:'Alice',references:[{id:'m1',reference:'MOV-001',name:'Papier <img src=x onerror=alert(1)>',quantity:5,amount:12.5}],links:[],total:1}];
 });
 const panel=page.locator('.cocoGlobalHistory .cocoFollowup');if(width<900)await panel.locator(':scope>summary').click();await panel.locator('[data-refresh]').click();
 await expect(panel.locator('.cocoFollowupEventTitle')).toHaveText('Réception d’achat');await expect(panel.locator('.cocoFollowupAudit')).toHaveText('Piste d’audit');
 await expect(panel.locator('.cocoFollowupReferences')).toContainText('Quantité: 5');await expect(panel.locator('.cocoFollowupReferences')).toContainText('Montant: 12,50');await expect(panel.locator('.cocoFollowupReferences img')).toHaveCount(0);
 await panel.locator('[data-refresh]').click();await expect(panel.locator('.cocoFollowupAudit')).toHaveCount(1);await panel.locator('[data-filter=notes]').click();await expect(panel.locator('.cocoFollowupAudit')).toHaveCount(0);await panel.locator('[data-filter=actions]').click();await expect(panel.locator('.cocoFollowupAudit')).toHaveCount(1);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
});

for(const width of [390,1440])test(`Agent Coco central history identifies source modules and keeps dossier links at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});await setup(page,{module:'assistant-ia'});
 await page.evaluate(()=>{window.__moduleHistory=[
  {id:'central-product',module_id:'products',at:'2026-10-20T15:00:00Z',type:'action',action:'update',subject:'Producto',actor_name:'Agent Coco',source_type:'chat',source_label:'Agent Coco · Claude',references:[{reference:'PAP-01'}],links:[{module:'products',action:'module'}],total:2},
  {id:'central-order',module_id:'sales-orders',at:'2026-10-20T14:00:00Z',type:'note',action:'note',subject:'Suivi',body:'Suivi du dossier par Agent Coco.',actor_name:'Agent Coco',references:[{reference:'PV-000001'}],links:[{module:'sales-orders',action:'order',id:'10000000-0000-4000-8000-000000000001',reference:'PV-000001'}],total:2}
 ];window.__centralOpened=null;window.GamaSales.openOrder=async id=>{window.__centralOpened=id}});
 const panel=page.locator('.cocoGlobalHistory .cocoFollowup');await expect(panel).toHaveAttribute('open','');await panel.locator('[data-refresh]').click();
 await expect(panel.locator('.cocoFollowupTitle')).toHaveText('Historique central d’Agent Coco');
 await expect(panel.locator('.cocoFollowupOrigin')).toHaveText(['Produits','Ventes']);await expect(panel.locator('.is-agent')).toHaveCount(2);
 await panel.locator('[data-refresh]').click();await expect(panel.locator('.cocoFollowupEvent')).toHaveCount(2);
 await panel.locator('[data-filter=actions]').click();await expect(panel.locator('.cocoFollowupEvent')).toHaveCount(1);
 await panel.locator('[data-filter=notes]').click();await expect(panel).toContainText('Suivi du dossier par Agent Coco.');
 await panel.getByRole('button',{name:/PV-000001/}).click();expect(await page.evaluate(()=>window.__centralOpened)).toBe('10000000-0000-4000-8000-000000000001');
 await panel.locator('[data-filter=all]').click();expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
 const bounds=await page.evaluate(()=>{const history=document.querySelector('.cocoAgentHistory'),section=document.getElementById('assistant-ia'),form=document.getElementById('aiForm');return {history:history.getBoundingClientRect().toJSON(),section:section.getBoundingClientRect().toJSON(),form:form.getBoundingClientRect().toJSON(),position:getComputedStyle(history.querySelector('.cocoFollowup')).position,timeline:getComputedStyle(history.querySelector('.cocoFollowupTimeline')).maxHeight}});
 expect(bounds.history.y).toBeGreaterThanOrEqual(bounds.form.bottom);expect(Math.abs(bounds.history.width-bounds.section.width)).toBeLessThan(2);expect(bounds.position).toBe('static');expect(bounds.timeline).toBe('none');
 await page.locator('#agentReportsTab').click();await expect(panel).toBeVisible();await page.locator('#agentChatTab').click();await expect(panel).toBeVisible();
 await page.evaluate(()=>window.scrollTo({top:0,behavior:'instant'}));
 await page.screenshot({path:`test-results/central-agent-${width}.png`,fullPage:true});
 await page.evaluate(()=>window.GamaAssistant.open());await expect(page.locator('.cocoAgentHistory')).toHaveCount(1);await expect(page.locator('.cocoAgentHistory .cocoFollowup')).toHaveAttribute('open','');
 await page.evaluate(()=>window.ArcRouter.open('products'));await expect(page.locator('.cocoAgentHistory')).toHaveCount(0);await expect(page.locator('.arcContent')).toHaveClass(/cocoHasModuleHistory/);
});

for(const module of ['contacts','assistant-ia'])for(const width of [390,1440])test(`pending approval tab filters ${module} history at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});await setup(page,{module,proposal:true});
 const panel=page.locator('.cocoFollowup');if(width<900&&module!=='assistant-ia')await panel.locator(':scope>summary').click();
 await panel.getByRole('button',{name:'À traiter',exact:true}).click();
 await expect(panel.locator('.cocoFollowupEvent')).toHaveCount(1);await expect(panel.locator('[data-review-proposal]')).toBeVisible();
 expect(await page.evaluate(()=>window.__moduleCalls.some(c=>c.p_action==='list'&&c.p_data.pending_only===true))).toBe(true);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
 await page.screenshot({path:`test-results/history-pending-${module}-${width}.png`,fullPage:true});
 await panel.locator('[data-reject-proposal]').click();await expect(panel.locator('.cocoFollowupEmpty')).toHaveText('Aucune action en attente d’approbation.');
 await panel.locator('[data-filter=proposals]').click();await expect(panel.locator('.cocoProposalState')).toHaveText('Refusé');
});

for(const module of ['contacts','assistant-ia'])test(`approval and rejection show the human reviewer in ${module}`,async({page})=>{
 await setup(page,{module});
 await page.evaluate(()=>{window.__moduleHistory=[
  {id:'proposal',type:'proposal',action:'proposal',subject:'mail_analysis',actor_name:'Agent Coco',at:'2026-10-20T12:00:00Z',links:[]},
  ...['approved','rejected'].map((state,i)=>({id:state,type:'action',action:i?'reject_proposal':'approve_proposal',subject:'proposal_'+state,actor_id:'alice',actor_name:'Alice Reviewer',source_type:'chat',source_label:'Agent Coco',at:`2026-10-20T12:0${i+1}:00Z`,links:[]}))
 ]});
 const panel=page.locator('.cocoGlobalHistory .cocoFollowup');await panel.locator('[data-refresh]').click();
 for(const title of ['Proposition validée','Proposition refusée']){
  const event=panel.locator('.cocoFollowupEvent').filter({has:page.locator('.cocoFollowupEventTitle',{hasText:title})});
  await expect(event.locator('.cocoFollowupWho strong')).toHaveText('Alice Reviewer');
  await expect(event.locator('.cocoFollowupAvatar')).not.toHaveClass(/is-agent/);
 }
 await expect(panel.locator('.cocoFollowupAvatar.is-agent')).toHaveCount(1);
});
