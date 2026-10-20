const {test,expect}=require('@playwright/test');
const {boot}=require('./order-followup-fixture.cjs');
const product='20000000-0000-4000-8000-000000000001',record='30000000-0000-4000-8000-000000000001';
async function contextHistory(page,language='fr'){
 await boot(page,{language});
 await page.evaluate(async({product,record})=>{
  const context={module_id:'warehouses',actor_id:'alice',number:'Stock',status:'recorded',can_note:false,stages:[]};
  window.__contextHistory=[{id:'stock-change',module_id:'warehouses',record_table:'stock_quants',at:'2026-10-20T18:42:15Z',type:'action',action:'update',subject:'Almacenes y existencias',actor_id:'alice',actor_name:'Jimmy Lisciandra',action_count:2,source_type:'erp',references:[
   {kind:'product',id:product,record_id:record,reference:'DVDG005',name:'DVD grabable cono de 25',quantity:8,quantity_mode:'snapshot',context:{location:'Quito · A-01 · Estante',changes:[{field:'quantity',before:5,after:8},{field:'reserved_quantity',before:0,after:2}]}},
   {kind:'product',id:product,record_id:'second-position',reference:'DVDG005',name:'DVD grabable cono de 25',quantity:3,quantity_mode:'snapshot',context:{location:'Quito · B-02 · Estante',changes:[{field:'quantity',before:6,after:3}]}}
  ],links:[{module:'warehouses',action:'module',id:record,reference:record},{module:'warehouses',action:'module',id:'second-position',reference:'second-position'},{module:'warehouses',action:'stock_product',id:product,reference:'DVDG005'}]}];
  const original=window.GamaCloud.db;window.GamaCloud.db=async()=>{const client=await original();return {...client,rpc:async(name,args)=>name==='coco_module_history'?{data:args.p_action==='context'?context:{context,history:window.__contextHistory,entries:[],proposals:[],portraits:{}}}:client.rpc(name,args)}};
  await window.ArcRouter.open('warehouses');
 },{product,record});
 await expect(page.locator('.cocoGlobalHistory .cocoFollowupParty')).toBeAttached();
}
for(const width of [390,1440])test(`stock action context is clear, non-additive and usable at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:1000});await contextHistory(page);
 const panel=page.locator('.cocoFollowup');if(width<900)await panel.locator(':scope>summary').click();
 await expect(panel.locator('.cocoFollowupWho')).toContainText('Jimmy Lisciandra');await expect(panel.locator('time')).toContainText('13:42:15');
 await expect(panel.locator('.cocoFollowupEventTitle')).toHaveText('Stock par emplacement · Modification');
 await expect(panel.locator('.cocoFollowupContext')).toContainText('CommentDepuis l’ERP');
 await expect(panel.locator('.cocoFollowupReferences')).toContainText('5 → 8');await expect(panel.locator('.cocoFollowupReferences')).toContainText('6 → 3');
 await expect(panel.locator('.cocoFollowupReferences li')).toHaveCount(2);await expect(panel).not.toContainText('Quantité: 11');await expect(panel).not.toContainText(record);
 await panel.locator('.cocoFollowupChanges summary').click();await expect(panel.locator('.cocoFollowupChanges')).toContainText('Réservé0 → 2');
 await expect(panel.locator('[data-followup-link]')).toHaveCount(1);
 await page.screenshot({path:`test-results/history-context-${width}.png`,fullPage:true});
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
 await page.evaluate(()=>{window.__contextOpen=[];window.ArcRouter.open=async m=>window.__contextOpen.push(m);window.GamaInventoryV2={focusProduct:async id=>window.__contextOpen.push(id)}});
 await panel.getByRole('button',{name:/Voir le stock/}).click();expect(await page.evaluate(()=>window.__contextOpen)).toEqual(['warehouses',product]);
});
test('old module UUID links collapse to one honest module destination; document links open exact records',async({page})=>{
 await contextHistory(page);await page.evaluate(()=>{
  window.__contextHistory=[{id:'legacy',module_id:'warehouses',at:'2026-10-20T18:42:00Z',type:'action',action:'update',subject:'Almacenes y existencias',actor_name:'AUTHOR_NOT_RECORDED',links:[{module:'warehouses',action:'module',id:'20000000-0000-4000-8000-000000000001',reference:'20000000-0000-4000-8000-000000000001'},{module:'warehouses',action:'module',id:'other'}]},
  {id:'doc',module_id:'documents',record_table:'business_documents',at:'2026-10-20T18:43:00Z',type:'action',action:'insert',subject:'Documento',actor_name:'Agent Coco',source_type:'chat',links:[{module:'documents',action:'module',id:'doc-1',reference:'DOC-001'}]}];
 });await page.locator('[data-refresh]').click();
 await expect(page.locator('.cocoFollowupLinks')).toHaveCount(2);await expect(page.locator('[data-followup-link]')).toHaveCount(2);
 await expect(page.locator('.cocoFollowupTimeline')).toContainText('Origine non enregistrée');await expect(page.locator('.cocoFollowupTimeline')).toContainText('Quantité et montant non enregistrés');
 await expect(page.getByRole('button',{name:'Ouvrir le module · Stock / entrepôts'})).toBeVisible();
 await page.evaluate(()=>{window.__docOpened=[];window.ArcRouter.open=async m=>window.__docOpened.push(m);window.GamaDocuments={openRecord:async id=>window.__docOpened.push(id)}});
 await page.getByRole('button',{name:'Ouvrir le document · DOC-001'}).click();expect(await page.evaluate(()=>window.__docOpened)).toEqual(['documents','doc-1']);
});
test('same-time dossier actions from different sources or executors stay separate',async({page})=>{
 await boot(page);await page.evaluate(()=>{
  window.__history=[];const event={type:'action',subject:'reserve',actor_id:'alice',actor_name:'Alice',created_at:'2026-10-20T18:42:00.123456Z',kind:'sales',order_id:'order-a',source_type:'erp'};
  window.__entries=[{...event,id:'a'},{...event,id:'b'},{...event,id:'c',source_type:'import'},{...event,id:'d',source_type:'chat',actor_name:'Agent Coco'},{...event,id:'e',source_type:'chat',actor_name:'Agent Coco',source_id:'other-request'}];
 });await page.locator('[data-refresh]').click();await expect(page.locator('.cocoFollowupEvent')).toHaveCount(4);await expect(page.locator('[data-action-count="2"]')).toHaveCount(1);
});
for(const language of ['es','en'])test(`context and detail labels support ${language}`,async({page})=>{
 await contextHistory(page,language);await expect(page.locator('.cocoFollowupContext')).toContainText(language==='es'?'Desde el ERP':'Through the ERP');
 await page.locator('.cocoFollowupChanges summary').click();await expect(page.locator('.cocoFollowupChanges')).toContainText(language==='es'?'Reservado':'Reserved');
});

for(const width of [390,1440])test(`dossier pending tab removes approved actions at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});await boot(page,{proposal:true});const panel=page.locator('.cocoFollowup');if(width<900)await panel.locator(':scope>summary').click();
 await panel.getByRole('button',{name:'À traiter',exact:true}).click();await expect(panel.locator('.cocoFollowupEvent')).toHaveCount(1);
 await panel.locator('[data-review-proposal]').click();const dialog=page.locator('.cocoProposalDialog');await dialog.locator('[data-check]').click();await expect(dialog.locator('[type=submit]')).toBeEnabled();await dialog.locator('[type=submit]').click();
 await expect(panel.locator('.cocoFollowupEmpty')).toHaveText('Aucune action en attente d’approbation.');
 await panel.locator('[data-filter=proposals]').click();await expect(panel.locator('.cocoProposalState')).toHaveText('Validé');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
});
