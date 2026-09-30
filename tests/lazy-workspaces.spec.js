const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
test('home defers optional workspaces and direct navigation still opens them',async({page})=>{
 await page.addInitScript(()=>localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'})));
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.route('https://**/*',r=>r.abort());
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());
 const downloaded=()=>page.evaluate(()=>performance.getEntriesByType('resource').map(r=>new URL(r.name).pathname));
 expect((await downloaded()).some(x=>/gama-(knowledge|assistant-ia|tms-module)\.js$/.test(x))).toBe(false);
 await page.evaluate(()=>GamaKnowledge.open());await expect(page.locator('#knowledge')).toBeVisible();
 await page.evaluate(()=>ArcRouter.open('tms'));await expect(page.locator('#gama-tms-section')).toBeVisible();
 expect((await downloaded()).filter(x=>x.endsWith('gama-knowledge.js'))).toHaveLength(1);
 await page.evaluate(()=>GamaKnowledge.open());expect((await downloaded()).filter(x=>x.endsWith('gama-knowledge.js'))).toHaveLength(1);
});
