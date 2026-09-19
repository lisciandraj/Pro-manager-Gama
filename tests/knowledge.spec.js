const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const guide=fs.readFileSync(path.join(__dirname,'../supabase/legacy-migrations/20260914213512_knowledge_base.sql'),'utf8').split('$guide$')[1];
const bridge=`(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,from(table){if(table!=='knowledge_articles')return c.from(table);let mode='read',payload,filters=[];const q={select(){return q},order(){return q},eq(k,v){filters.push([k,v]);return q},update(data){mode='update';payload=data;return q},insert(data){mode='insert';payload=data;return q},async range(a,b){__knowledgeReads++;return __knowledgeError?{error:{message:'NETWORK'}}:{data:structuredClone(__knowledge.slice(a,b+1))}},async single(){return q.maybeSingle()},async maybeSingle(){if(__knowledgeError)return {error:{message:'NETWORK'}};if(mode==='insert'){const row={id:crypto.randomUUID(),version:1,updated_at:new Date().toISOString(),...payload};__knowledge.push(row);localStorage.setItem('qa-knowledge',JSON.stringify(__knowledge));return {data:structuredClone(row)}}const row=__knowledge.find(r=>filters.every(([k,v])=>r[k]===v));if(!row)return {data:null};Object.assign(row,payload,{version:row.version+1,updated_at:new Date().toISOString()});localStorage.setItem('qa-knowledge',JSON.stringify(__knowledge));return {data:structuredClone(row)}}};return q}}}})();`;
async function boot(page,role='admin'){
 await page.addInitScript(({role,guide})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Knowledge QA'}));window.__knowledge=JSON.parse(localStorage.getItem('qa-knowledge')||'null')||[{id:'guide',slug:'gama-getting-started',parent_id:null,title:'Bien démarrer avec GAMA ERP',body:guide,properties:[],version:1,updated_at:'2026-09-14T12:00:00Z'}];window.__knowledgeError=false;window.__knowledgeReads=0},{role,guide});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+bridge}));await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
}
async function open(page){await page.locator('#mainmenu [data-gama-module="knowledge"]').click();await expect(page.locator('#gkArticleTitle')).toHaveText('Bien démarrer avec GAMA ERP')}
test('create nested articles, customize all property types, search and reload persisted content',async({page})=>{
 await boot(page);await open(page);await expect(page.locator('#gkMain')).toContainText('Paiements');
 await page.locator('#gkChild').click();await page.locator('#gkTitle').fill('Réception entrepôt');await page.locator('#gkBody').fill('# Contrôle\nScanner **chaque colis**.\n- Vérifier les quantités\n<img src=x onerror=alert(1)>');
 for(const [label,type,value] of [['Service','text','Logistique Nord'],['Quantité','number','0'],['Révision','date','2026-12-01'],['Validé','boolean','true'],['Catégorie','select','Procédure']]){
  await page.locator('#gkAddProperty').click();const p=page.locator('.gkProperty').last();await p.locator('.gkLabel').fill(label);await p.locator('.gkType').selectOption(type);
  if(type==='select'){await p.locator('.gkOptions').fill('Guide, Procédure');await p.locator('.gkOptions').blur()}
  if(['boolean','select'].includes(type))await p.locator('.gkValue').selectOption(value);else await p.locator('.gkValue').fill(value);
 }
 await page.locator('#gkPreviewButton').click();await expect(page.locator('#gkPreview strong')).toHaveText('chaque colis');await expect(page.locator('#gkPreview img')).toHaveCount(0);
 await page.locator('#gkSave').click();await expect(page.locator('#gkArticleTitle')).toHaveText('Réception entrepôt');await expect(page.locator('.gkProps')).toContainText('0');
 await page.locator('#gkChild').click();await page.locator('#gkTitle').fill('Contrôle final');await page.locator('#gkBody').fill('Inspection terminée');await page.locator('#gkSave').click();await expect(page.locator('.gkCrumbs button')).toHaveCount(2);
 await page.locator('#gkSearch').fill('logistique nord');await expect(page.locator('.gkResult')).toHaveCount(1);await page.locator('.gkResult').click();await expect(page.locator('#gkArticleTitle')).toHaveText('Réception entrepôt');
 await page.locator('#gkEdit').click();await page.locator('#gkTitle').fill('Réception validée');await page.locator('#gkSave').click();await expect(page.locator('#gkArticleTitle')).toHaveText('Réception validée');
 await page.reload();await open(page);await page.locator('#gkSearch').fill('reception validee');await page.locator('.gkResult').filter({hasText:'Réception validée'}).click();await expect(page.locator('#gkArticleTitle')).toHaveText('Réception validée');expect(await page.evaluate(()=>__knowledge.length)).toBe(3);
});
test('save errors and concurrent edits retain the draft; retry and discard work',async({page})=>{
 await boot(page);await open(page);await page.locator('#gkEdit').click();await page.locator('#gkBody').fill('Draft to preserve');await page.evaluate(()=>__knowledgeError=true);await page.locator('#gkSave').click();await expect(page.locator('#gkMessage')).toContainText('NETWORK');await expect(page.locator('#gkBody')).toHaveValue('Draft to preserve');
 await page.evaluate(()=>{__knowledgeError=false;__knowledge[0].version++});await page.locator('#gkSave').click();await expect(page.locator('#gkMessage')).toContainText('otra persona');await expect(page.locator('#gkBody')).toHaveValue('Draft to preserve');
 page.once('dialog',d=>d.dismiss());await page.locator('#gkCancel').click();await expect(page.locator('#gkBody')).toBeVisible();page.once('dialog',d=>d.accept());await page.locator('#gkCancel').click();await expect(page.locator('#gkBody')).toHaveCount(0);
 await page.evaluate(()=>__knowledgeError=true);await page.locator('#gkReload').click();await expect(page.locator('#gkMessage')).toContainText('No se pudieron cargar');await page.evaluate(()=>__knowledgeError=false);await page.locator('#gkReload').click();await expect(page.locator('#gkArticleTitle')).toBeVisible();
});
for(const role of ['commercial','magasinier','client'])test('access for '+role,async({page})=>{
 await boot(page,role);
 if(role==='client'){await expect(page.locator('#mainmenu [data-gama-module="knowledge"]')).toBeHidden();await page.evaluate(()=>GamaKnowledge.open());expect(await page.evaluate(()=>__knowledgeReads)).toBe(0);await expect(page.locator('#knowledge')).toHaveCount(0)}
 else{await open(page);await expect(page.locator('#gkNew')).toHaveCount(0);await expect(page.locator('#gkEdit')).toHaveCount(0);await page.locator('#gkSearch').fill('scanner');await expect(page.locator('.gkResult')).toHaveCount(1)}
});
test('mobile French interface, editor layout and disabled module',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(()=>GamaI18n.setLanguage('fr'));await open(page);await expect(page.locator('#knowledge')).toContainText('Base de connaissances');await page.screenshot({path:'test-results/knowledge-mobile.png',fullPage:true});
 await page.locator('#gkNew').click();await page.locator('#gkAddProperty').click();await expect(page.locator('.gkOptionsLabel')).toBeHidden();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);await page.screenshot({path:'test-results/knowledge-editor-mobile.png',fullPage:true});
 page.once('dialog',d=>d.accept());await page.locator('#gkCancel').click();await page.evaluate(()=>{GamaModules.enabled=id=>id!=='knowledge';__knowledgeReads=0;GamaKnowledge.open()});expect(await page.evaluate(()=>__knowledgeReads)).toBe(0);
});
