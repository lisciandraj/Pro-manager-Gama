const {test,expect}=require('@playwright/test'),fs=require('node:fs'),path=require('node:path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
async function boot(page){
 await page.addInitScript(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Queue QA'}));localStorage.setItem('gama_language_v1','fr')});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;GamaCloud.getSession=async()=>({data:{session:{access_token:'isolated',user:{id:'qa'}}}});`}));
 await page.route('**/functions/v1/gama-assistant-ia',r=>r.fulfill({contentType:'application/json',body:JSON.stringify(r.request().postDataJSON().action==='status'?{configured:false}:{rows:[]})}));
 await page.goto('/index.html');await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
 await page.evaluate(()=>{const original=ArcData.rpc;window.__queueCalls=[];window.__executed=false;window.__queueDelay=false;window.ArcData={...ArcData,rpc:async(n,a)=>{if(n!=='coco_action_queue')return original(n,a);__queueCalls.push(a);const {p_action:action,p_data:d}=a;
 if(action==='list')return {total:__executed?0:2,rows:__executed?[]:[{id:'one',module_id:'accounting',action:'bank_settlement',summary:'FAC-001 · 100 USD',source_label:'Agent Coco',created_at:'2026-10-20T12:00:00Z'},{id:'two',module_id:'contacts',action:'contact_draft',summary:'Contact <script>unsafe</script>',source_label:'Agent Coco',created_at:'2026-10-20T12:00:00Z'}]};
 if(action==='review_batch'){if(__queueDelay)await new Promise(resolve=>window.__resolveQueue=resolve);return {rows:d.items.map(x=>({id:x.id,ok:x.id==='one',error:'CONTACT_INVALID_DATA',summary:'FAC-001 · 100 USD',result:{hash:'review-hash',review:{details:['FAC-001 · Client'],settlement:{currency:'USD',amount:100,balance_before:115,balance_after:15}}}}))}};
 if(action==='approve_batch'){__executed=true;return {rows:d.items.map(x=>({...x,ok:true,result:{id:'payment'}}))}};
 if(action==='reject_batch')return {rows:d.items.map(x=>({...x,ok:true}))};throw Error('Unexpected '+action);
 }};});
 await page.locator('#mainmenu [data-gama-module="assistant-ia"]').click();await page.locator('#agentQueueTab').click();await expect(page.locator('[data-queue-id]')).toHaveCount(2);
}
test('queue reviews separately, executes only valid selected items, then requires fresh selection',async({page})=>{
 await boot(page);await expect(page.locator('#agentQueueReview')).toBeDisabled();await expect(page.locator('#agentQueueRows')).toContainText('Contact <script>unsafe</script>');
 await page.locator('[data-queue-id="one"]').check();await page.locator('[data-queue-id="two"]').check();await page.locator('#agentQueueReview').click();
 await expect(page.locator('#agentQueueConfirm')).toHaveText('Valider et exécuter (1)');await expect(page.locator('#agentQueuePreview')).toContainText('Solde après');
 expect(await page.evaluate(()=>__queueCalls.some(x=>x.p_action==='approve_batch'))).toBe(false);
 await page.locator('#agentQueueConfirm').click();await expect(page.locator('#agentQueueDone')).toBeVisible();expect(await page.evaluate(()=>__queueCalls.find(x=>x.p_action==='approve_batch').p_data)).toEqual({confirmed:true,items:[{id:'one',hash:'review-hash'}]});
 await expect(page.locator('#agentQueueReview')).toBeDisabled();await page.locator('#agentQueueRefresh').click();await expect(page.locator('#agentQueueRows')).toContainText('Aucune action');
});
test('selection changes invalidate review and reject has a separate confirmation',async({page})=>{
 await boot(page);await page.locator('[data-queue-id="one"]').check();await page.locator('#agentQueueReview').click();await expect(page.locator('#agentQueueConfirm')).toBeVisible();await page.locator('[data-queue-id="two"]').check();await expect(page.locator('#agentQueueConfirm')).toHaveCount(0);
 await page.locator('#agentQueueReject').click();await expect(page.locator('#agentQueueConfirm')).toHaveText('Confirmer le refus (2)');expect(await page.evaluate(()=>__queueCalls.some(x=>x.p_action==='reject_batch'))).toBe(false);await page.locator('#agentQueueCancel').click();await expect(page.locator('#agentQueueConfirm')).toHaveCount(0);
});
test('queue fits mobile, supports tab keyboard navigation, and drops responses after sign-out',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.locator('#agentQueueTab').focus();await page.keyboard.press('ArrowRight');await expect(page.locator('#agentReportsTab')).toBeFocused();await page.keyboard.press('ArrowLeft');await expect(page.locator('#agentQueueTab')).toBeFocused();await expect(page.locator('[data-queue-id]')).toHaveCount(2);
 await page.locator('[data-queue-id="one"]').check();await page.locator('#agentQueueReview').click();await expect(page.locator('#agentQueueConfirm')).toBeVisible();await page.screenshot({path:'test-results/agent-queue-mobile.png',fullPage:true});
 expect(await page.evaluate(()=>document.querySelector('#agentQueue').scrollWidth<=document.querySelector('#agentQueue').clientWidth+1)).toBe(true);
 await page.locator('#agentQueueCancel').click();await page.evaluate(()=>__queueDelay=true);await page.locator('#agentQueueReview').click();await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await page.evaluate(()=>__resolveQueue());await expect(page.locator('#agentQueueConfirm')).toHaveCount(0);
});
