const {test,expect}=require('@playwright/test');
const fs=require('fs');const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
for(const role of ['admin','client'])test(`retired customer modules are absent and denied for ${role}`,async({page})=>{
 await page.addInitScript(role=>localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Test'})),role);
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');await page.waitForFunction(()=>window.gamaAccessAllowed);
 expect(await page.evaluate(()=>['client-catalog','client-deliveries'].map(id=>gamaAccessAllowed(id)))).toEqual([false,false]);
 await expect(page.locator('[data-gama-module="client-catalog"],[data-gama-module="client-deliveries"]')).toHaveCount(0);
});
