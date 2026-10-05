const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
for(const width of [390,1440])test(`manual mail handoff preserves content and requires sending confirmation (${width}px)`,async({page})=>{
 await page.setViewportSize({width,height:900});
 await page.addInitScript(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Mail QA'}));localStorage.setItem('gama_language_v1','fr')});
 await page.route('**/gama-supabase.js*',route=>route.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
 await page.waitForFunction(()=>window.ArcUI&&window.ArcData);
 if(!await page.evaluate(()=>!!window.CocoFlows))await page.addScriptTag({url:'/coco-flow-tools.js'});
 await page.evaluate(()=>{
  window.__mailCalls=[];window.__draft={id:'11111111-1111-4111-8111-111111111111',kind:'invoice_reminder',state:'draft',recipient:'client+test@example.com',subject:'GAMA · facture & suivi',body:'Bonjour Ana,\nSolde : 115 USD.\nLien : https://example.invalid/?a=1&b=2\nMerci !'};
  const original=ArcData.rpc;ArcData.rpc=async(name,args)=>{if(name!=='gama_messages')return original(name,args);__mailCalls.push(args);if(args.p_action==='context')return {mode:'manual',outbox:[__draft]};if(args.p_action==='manual_sent'){__draft.state='sent_manually';__draft.manual_sent_at=new Date().toISOString();return {state:__draft.state}}return {...__draft}};
 });
 await page.evaluate(()=>CocoFlows.messages());await page.locator('[data-message-draft]').click();
 await expect(page.locator('[data-compose=gmail]')).toBeVisible();
 for(const [provider,subjectParam] of [['gmail','su'],['outlook','subject'],['office','subject']]){
  const url=new URL(await page.locator(`[data-compose=${provider}]`).getAttribute('href'));
  expect(url.searchParams.get('to')).toBe('client+test@example.com');expect(url.searchParams.get(subjectParam)).toBe('GAMA · facture & suivi');expect(url.searchParams.get('body')).toBe('Bonjour Ana,\nSolde : 115 USD.\nLien : https://example.invalid/?a=1&b=2\nMerci !');
 }
 expect(await page.evaluate(()=>__mailCalls.filter(c=>c.p_action==='manual_sent').length)).toBe(0);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 await page.locator('[name=confirmed]').check();await page.getByRole('button',{name:'Confirmer l’envoi',exact:true}).click();
 await expect(page.locator('[data-message-draft]')).toHaveCount(0);expect(await page.evaluate(()=>__mailCalls.filter(c=>c.p_action==='manual_sent').map(c=>c.p_data.confirmed))).toEqual([true]);await expect(page.locator('dialog').last()).toContainText('confirmation manuelle');
});
