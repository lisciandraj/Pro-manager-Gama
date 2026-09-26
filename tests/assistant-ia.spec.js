const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const id='22222222-2222-4222-8222-222222222222';
const answer={id,engine:'openai',as_of:'2026-09-15T12:00:00Z',period:{from:'2026-09-01',to:'2026-09-15'},report:{title:'Analyse des priorités',summary:'Trois produits sous le seuil.',findings:[{title:'Stock disponible',detail:'<img src=x onerror=alert(1)>',evidence_ids:['S1']}],actions:[{priority:'P1',title:'Préparer un réapprovisionnement',owner:'Achats',due:'Sous 2 jours',steps:['Vérifier les achats ouverts','Valider les quantités'],success_metric:'Produits couverts',evidence_ids:['S1']}],limitations:['Données actuelles'],follow_up_questions:['Quels achats sont en retard ?']},coverage:[{table:'products',module:'products',rows:250}],evidence:[{id:'S1',kind:'query_data',label:'products',module:'products',as_of:'2026-09-15T12:00:00Z',data:{matched_rows:250,rows:[{name:'Produit A',stock:2}],truncated:true}}]};
async function boot(page,{role='admin',configured=true}={}){
 await page.addInitScript(({role})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Assistant QA'}));localStorage.setItem('gama_language_v1','fr');window.__aiRequests=[];},{role});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;GamaCloud.getSession=async()=>({data:{session:{access_token:'qa-token',user:{id:'qa'}}}});
 window.__cocoCalls=[];window.__cocoCount=27;window.__cocoError=false;
 const originalCocoRpc=GamaCloud.rpc;
 GamaCloud.rpc=async(name,args={})=>{
  if(!name.startsWith('gama_coco'))return originalCocoRpc(name,args);
  __cocoCalls.push({name,args});
  if(window.__cocoDelay)await new Promise(resolve=>window.__cocoResolve=resolve);
  if(window.__cocoError)return {error:{code:'503',message:'Network unavailable'}};
  if(name==='gama_coco_inventory_analyze')return {data:{products_analyzed:30}};
  return {data:{calculated_at:new Date().toISOString(),products_analyzed:30,without_history:25,reorder_count:__cocoCount,critical_count:2,recommendation_count:__cocoCount,has_more:(args.p_offset||0)+25<__cocoCount,
   recommendations:Array.from({length:Math.min(25,Math.max(0,__cocoCount-(args.p_offset||0)))},(_,i)=>({id:String(i+(args.p_offset||0)),product_name:'Produit '+(i+(args.p_offset||0)+1),priority:i===0?'critical':'high',recommendation_type:'reorder',confidence:20,current_value:{available_stock:5,incoming_stock:2,draft_purchase_stock:1,min:10,max:30},recommended_value:{min:10,max:30,order_qty:22},reasoning:{basis:'configured_thresholds',demand_30d:0,demand_60d:0,demand_90d:0,lead_time_days:7}}))}};
 };
`}));
 await page.route('**/functions/v1/gama-assistant-ia',async r=>{const b=r.request().postDataJSON();await page.evaluate(b=>__aiRequests.push(b),b);let data;
  if(b.action==='status')data={configured,model:configured?'gpt-4.1-mini':null};
  else if(b.action==='history')data={rows:[]};
  else if(b.action==='conversation')data={id,question:'Analyse initiale',answer};
  else if(b.action==='configure'){configured=true;data={configured:true,model:'gpt-4.1-mini'};}
  else data={...answer,engine:b.action==='diagnostic'?'calculated':'openai'};
  await r.fulfill({contentType:'application/json',body:JSON.stringify(data)});
 });
 await page.goto('/index.html');await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
}
async function open(page){await page.locator('#mainmenu [data-gama-module="assistant-ia"]').click();await expect(page.locator('#aiConfigure')).toBeVisible();}
test('admin chat, structured plans, source evidence, follow-up, history and logout clearing',async({page})=>{
 await boot(page);await open(page);await expect(page.locator('#assistant-ia h2')).toHaveText('Coco Intelligence');
 await page.locator('#aiQuestion').fill('Analyse mon entreprise');await page.locator('#aiSend').click();await expect(page.locator('.ai-answer h3')).toHaveText('Analyse des priorités');await expect(page.locator('.ai-action')).toContainText('Sous 2 jours');await expect(page.locator('.ai-answer img')).toHaveCount(0);
 await page.locator('.ai-ref').first().click();await expect(page.locator('.ai-scroll table').first()).toContainText('Produit A');await expect(page.locator('#ai-0-S1')).toContainText('Extrait limité');
 await page.locator('[data-followup]').click();await expect(page.locator('#aiQuestion')).toHaveValue('Quels achats sont en retard ?');await page.locator('#aiSend').click();await expect(page.locator('.ai-answer')).toHaveCount(2);expect(await page.evaluate(()=>__aiRequests.filter(x=>x.action==='ask')[1].history_ids)).toEqual([id]);
 await page.locator('#aiNew').click();await expect(page.locator('.ai-answer')).toHaveCount(0);await page.locator('#aiHistory button').first().click();await expect(page.locator('.ai-answer')).toHaveCount(1);
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await expect(page.locator('#assistant-ia')).toBeEmpty();
});
for(const role of ['commercial','magasinier','client'])test('module and direct entry denied for '+role,async({page})=>{
 await boot(page,{role});await expect(page.locator('#mainmenu [data-gama-module="assistant-ia"]')).toBeHidden();await page.evaluate(()=>GamaAssistant.open());expect(await page.evaluate(()=>__aiRequests.length)).toBe(0);await expect(page.locator('#assistant-ia')).toHaveCount(0);
});
test('missing API key, secure configuration, diagnostic and mobile layout',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page,{configured:false});await open(page);await expect(page.locator('#aiSend')).toBeDisabled();await page.locator('#aiDiagnostic').click();await expect(page.locator('.ai-answer')).toContainText('sans génération IA');
 await page.locator('#aiConfigure').click();await page.locator('#aiKey').fill('sk-not-a-real-secret-for-ui-test');await page.locator('#aiSaveConfig').click();await expect(page.locator('#aiSend')).toBeEnabled();await expect(page.locator('#aiKey')).toHaveValue('');expect(await page.evaluate(()=>Object.values(localStorage).some(v=>String(v).includes('sk-not-a-real')))).toBe(false);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);await page.screenshot({path:'test-results/assistant-mobile.png',fullPage:true});
});
test('service error preserves question; disabled module clears existing analysis',async({page})=>{
 await boot(page);await open(page);await page.route('**/functions/v1/gama-assistant-ia',r=>r.fulfill({status:403,contentType:'application/json',body:JSON.stringify({error:'ADMIN_REQUIRED'})}));await page.locator('#aiQuestion').fill('Question conservée');await page.locator('#aiSend').click();await expect(page.locator('#aiError')).toContainText('administrateurs actifs');await expect(page.locator('#aiQuestion')).toHaveValue('Question conservée');await expect(page.locator('#aiSend')).toBeEnabled();
 await page.evaluate(()=>{GamaModules.enabled=id=>id!=='assistant-ia';window.dispatchEvent(new CustomEvent('gama:modules-change'));});await expect(page.locator('#assistant-ia')).toBeEmpty();
});
test('desktop surface and English labels',async({page})=>{
 await page.setViewportSize({width:1440,height:1000});await boot(page);await open(page);await page.locator('#aiQuestion').fill('Analyse');await page.locator('#aiSend').click();await expect(page.locator('.ai-answer')).toBeVisible();await page.screenshot({path:'test-results/assistant-desktop.png',fullPage:true});await page.evaluate(()=>GamaI18n.setLanguage('en'));await expect(page.locator('#assistant-ia h2')).toHaveText('Coco Intelligence');await expect(page.locator('#aiSend')).toHaveText('Analyze with AI');
});

test('Coco stock details, no-key access, refresh, pagination and language changes',async({page})=>{
 await boot(page,{configured:false});await open(page);const box=page.locator('#cocoInventoryInsights');
 await expect(box.locator('.coco-card')).toHaveCount(25);await expect(box).toContainText('produits sans consommation observée');
 await box.locator('summary').first().click();await expect(box).toContainText('Historique insuffisant');
 await expect(box.locator('.coco-values').first()).toContainText('Brouillons déduits');
 await box.locator('[data-coco-explain]').first().click();await expect(page.locator('#aiQuestion')).toHaveValue('Explique la recommandation de stock pour Produit 1');
 await page.locator('#cocoNext').click();await expect(box.locator('.coco-card')).toHaveCount(2);await expect(box).toContainText('Produit 26');await expect(page.locator('#cocoNext')).toBeDisabled();
 await page.locator('#cocoRefresh').click();await expect(box.locator('.coco-card')).toHaveCount(25);
 expect(await page.evaluate(()=>__cocoCalls.filter(x=>x.name==='gama_coco_inventory_analyze').length)).toBe(1);
 await page.setViewportSize({width:390,height:844});expect(await box.evaluate(e=>e.getBoundingClientRect().right<=window.innerWidth)).toBe(true);
 await page.screenshot({path:'test-results/coco-mobile.png',fullPage:true});
 await page.evaluate(()=>GamaI18n.setLanguage('es'));await expect(box).toContainText('Los umbrales propuestos');
 await page.setViewportSize({width:1440,height:1000});await page.screenshot({path:'test-results/coco-desktop.png',fullPage:true});
});
test('Coco errors are retryable and late responses cannot restore data after logout',async({page})=>{
 await boot(page);await page.evaluate(()=>window.__cocoError=true);await open(page);
 await expect(page.locator('#cocoInventoryInsights [role="alert"]')).toContainText('indisponible');
 await expect(page.locator('#cocoInventoryInsights')).not.toContainText('migration');
 await page.evaluate(()=>window.__cocoError=false);await page.locator('#cocoRetry').click();await expect(page.locator('.coco-card')).toHaveCount(25);
 await page.evaluate(()=>window.__cocoDelay=true);await page.locator('#cocoRefresh').click();
 await page.waitForFunction(()=>!!window.__cocoResolve);
 await page.evaluate(()=>{localStorage.removeItem('gama_session_v1');window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}}));window.__cocoResolve();});
 await expect(page.locator('#assistant-ia')).toBeEmpty();
});
