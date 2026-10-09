const {test,expect}=require('@playwright/test');
const fs=require('node:fs'),path=require('node:path');
test.setTimeout(30000);
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const product='11111111-1111-4111-8111-111111111111',command='22222222-2222-4222-8222-222222222222',location='33333333-3333-4333-8333-333333333333';
function proposal(){return {id:command,digest:'a'.repeat(64),expires_at:new Date(Date.now()+600000).toISOString(),snapshot:{reference:'MED001',name:'Acetaminofen 500 mg caja de 100',unit:'unit',reason:'consommation interne',lines:[{location_id:location,location:'AE07-04',expected_quantity:65,reserved:0,target_quantity:0}]}}}
async function boot(page){
 await page.addInitScript(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Agent QA'}));localStorage.setItem('gama_language_v1','fr')});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;GamaCloud.getSession=async()=>({data:{session:{access_token:'isolated-test-token',user:{id:'qa'}}}});`}));
 await page.route('**/functions/v1/gama-assistant-ia',r=>{const body=r.request().postDataJSON();return r.fulfill({contentType:'application/json',body:JSON.stringify(body.action==='stock_plan'?{status:'prepared',proposal:proposal()}:body.action==='status'?{configured:true,model:'test'}:{rows:[]})})});
 await page.goto('/index.html');await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
 await page.evaluate(({product,location,proposal})=>{
  const original=ArcData.rpc;window.__agentCalls=[];window.__agentStock=65;window.__agentExecutions=0;
  window.ArcData={...window.ArcData,rpc:async(name,args)=>{
   if(name!=='coco_agent')return original(name,args);const {p_action:a,p_data:d}=args;__agentCalls.push({a,d});
   if(a==='settings')return {enabled:true,can_write:true,client_ids:['read-only'],write_client_ids:[]};
   if(a==='configure')return d;
   if(a==='search')return {items:[{id:product,reference:'MED001',name:'Acetaminofen 500 mg caja de 100',base_unit:'unit'}]};
   if(a==='stock')return {product_id:product,unit:'unit',lot_tracking:false,locations:[{location_id:location,location:'AE07-04',available:65,quantity:65}]};
   if(a==='prepare')return proposal;
   if(a==='execute'){if(__agentStock){__agentStock=0;__agentExecutions++}return {status:'executed',stock_after:0,adjustments:[{id:'adjustment',erp_reference:'AJ-TEST'}]}};
   if(a==='status')return {status:'executed',stock_now:__agentStock,original_receipt:{status:'executed'},adjustments:[{id:'adjustment',reference:'AJ-TEST'}],movements:[{id:'movement',reference:'MOV-TEST',quantity:65,stock_before:65,stock_after:0,reason:'consommation interne'}]};
   if(a==='history')return {items:[]};throw Error('UNEXPECTED_ACTION');
  }};
 },{product,location,proposal:proposal()});
 await page.locator('#mainmenu [data-gama-module="assistant-ia"]').click();await expect(page.locator('#aiStockPlan')).toBeVisible();
}
test('stock proposal does not move stock until confirmation, then rereads the ledger',async({page})=>{
 await boot(page);await page.locator('#agentStockActions').click();const d=page.locator('[data-coco-agent]');
 await d.locator('[name=query]').fill('MED001');await d.locator('[data-search] button').click();await expect(d.locator('[data-movement]')).toBeVisible();await d.locator('[name=all_stock]').check();await d.locator('[name=reason]').fill('consommation interne');await d.locator('[data-movement] [type=submit]').click();await expect(d.locator('[data-confirm]')).toBeVisible();expect(await page.evaluate(()=>__agentStock)).toBe(65);
 await d.locator('[data-confirm]').click();await expect(d.locator('[data-preview]')).toContainText('Exécuté');expect(await page.evaluate(()=>__agentExecutions)).toBe(1);expect(await page.evaluate(()=>__agentCalls.slice(-2).map(c=>c.a))).toEqual(['execute','status']);
});
test('natural-language chat requires its own confirmation and shows the actual movement reference',async({page})=>{
 await boot(page);await page.locator('#aiQuestion').fill('Retire tout MED001 pour consommation interne');await page.locator('#aiStockPlan').click();const d=page.locator('[data-coco-agent]');await expect(d.locator('[data-confirm]')).toBeVisible();expect(await page.evaluate(()=>__agentExecutions)).toBe(0);await d.locator('[data-confirm]').click();await expect(d).toContainText('MOV-TEST');expect(await page.evaluate(()=>__agentExecutions)).toBe(1);
});
test('Agent Coco dialog fits a phone and closes at logout',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.locator('#agentStockActions').click();await expect(page.locator('[data-coco-agent] [name=query]')).toBeVisible();
 await page.screenshot({path:'test-results/coco-agent-mobile.png',fullPage:true});
 const dimensions=await page.evaluate(()=>{const d=document.querySelector('[data-coco-agent]'),r=d.getBoundingClientRect();return {viewport:innerWidth,left:r.left,right:r.right,width:r.width,content:d.scrollWidth,client:d.clientWidth,root:document.documentElement.scrollWidth}});
 console.log('Agent phone dimensions',dimensions);
 expect(dimensions.left).toBeGreaterThanOrEqual(0);expect(dimensions.right).toBeLessThanOrEqual(dimensions.viewport+1);expect(dimensions.content).toBeLessThanOrEqual(dimensions.client+1);
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await expect(page.locator('[data-coco-agent]')).toHaveCount(0);
});
test('OAuth write consent does not elevate a previously read-only client',async({page})=>{
 await boot(page);let saved=null;await page.exposeFunction('recordAgentConfig',data=>{saved=data});await page.route('https://client.example.invalid/callback**',r=>r.fulfill({body:'OAuth test complete'}));
 await page.evaluate(async()=>{
  await ArcLoadScript('coco-agent-stock.js');const original=ArcData.rpc;
  window.ArcData={...window.ArcData,rpc:async(n,a)=>{if(n==='coco_agent'&&a.p_action==='settings')return {enabled:true,can_write:true,client_ids:['read-only'],write_client_ids:[]};if(n==='coco_agent'&&a.p_action==='configure'){await window.recordAgentConfig(a.p_data);return a.p_data}return original(n,a)}};
  GamaCloud.db=async()=>({auth:{oauth:{getAuthorizationDetails:async()=>({data:{authorization_id:'request',client:{id:'new-client',name:'Agent Test'},scope:'email',redirect_uri:'https://client.example.invalid/callback'}}),approveAuthorization:async()=>({data:{redirect_url:'https://client.example.invalid/callback?code=isolated'}})}}});
  await CocoAgent.consent('request');
 });
 await page.locator('[data-write]').check();await page.locator('[data-approve]').click();await page.waitForURL('https://client.example.invalid/callback**');expect(saved.client_ids).toEqual(['read-only','new-client']);expect(saved.write_client_ids).toEqual(['new-client']);
});
test('a previously consented OAuth request returns to its client instead of stalling',async({page})=>{
 await boot(page);await page.route('https://client.example.invalid/callback**',r=>r.fulfill({body:'OAuth test complete'}));
 await page.evaluate(async()=>{await ArcLoadScript('coco-agent-stock.js');GamaCloud.db=async()=>({auth:{oauth:{getAuthorizationDetails:async()=>({data:{redirect_url:'https://client.example.invalid/callback?code=isolated'}})}}});await CocoAgent.consent('request')});
 await page.waitForURL('https://client.example.invalid/callback**');
});
