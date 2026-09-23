const {test,expect}=require('@playwright/test');
const fs=require('fs');const path=require('path');const crypto=require('crypto');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const bridge=`(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();const rpc=c.rpc;c.rpc=async(fn,a)=>fn==='gama_operations_action'?{data:{finance:true,metrics:{invoiced:1840,orders:7,late_deliveries:2},total:93,active_count:67,alerts:[]}}:rpc(fn,a);return c}})();`;
async function boot(page,role='admin'){
 await page.addInitScript(role=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Test User'}));localStorage.setItem('gama_language_v1','fr');window.__DB={products:[],customers:[{id:'c1',active:true,name:'Customer'}],suppliers:[],invoices:[],profiles:[],stock_movements:[]}},role);
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+bridge}));
 // Logo completo en la barra desplegada; en el carril plegado de la tableta, el robot solo.
 await page.goto('/index.html');await expect(page.locator('.arcBrand img:visible')).toHaveCount(1);
}
test('original logo, six-column reference, translated labels and truthful metrics',async({page})=>{
 await page.setViewportSize({width:1440,height:1000});await boot(page);
 await expect(page.locator('.gamaF2Kpi')).toHaveCount(4);
 await expect(page.locator('.gamaF2KpiValue')).toHaveText([/1.*840/, '7','2','1']);
 await expect(page.locator('.gamaF2Head h1')).toHaveText('Menu principal');
 await expect(page.locator('.gamaF2KpiLabel').first()).toHaveText('Facturation (mois)');
 const layout=await page.evaluate(()=>({columns:getComputedStyle(document.querySelector('.gamaF2Grid')).gridTemplateColumns.split(' ').length,nav:getComputedStyle(document.querySelector('.arcSidebar')).backgroundColor,fit:getComputedStyle(document.querySelector('.arcLogo')).objectFit,ratio:Math.round(document.querySelector('.arcLogo').naturalWidth/document.querySelector('.arcLogo').naturalHeight*10)/10}));
 // Seis por fila en pantalla de ordenador: la referencia eran cuatro, y con
 // ellas el menú no cabía de un vistazo. Por debajo de 1280 vuelven a ser
 // cuatro, porque a seis el rótulo deja de leerse; eso se comprueba abajo.
 expect(layout).toEqual({columns:6,nav:'rgb(38, 44, 78)',fit:'contain',ratio:2.1});
 await page.setViewportSize({width:1279,height:1000});await page.waitForTimeout(250);
 const estrecho=await page.evaluate(()=>getComputedStyle(document.querySelector('.gamaF2Grid')).gridTemplateColumns.split(' ').length);
 expect(estrecho,'por debajo de 1280 las tarjetas se quedan sin sitio para su rótulo').toBe(4);
 await page.setViewportSize({width:1440,height:1000});await page.waitForTimeout(250);
 await page.locator('#arcProfileButton').click();await expect(page.locator('#aclLogout')).toBeVisible();
 await page.keyboard.press('Escape');await expect(page.locator('#aclLogout')).toBeHidden();
 // Coco ERP: el archivo oficial se conserva sin retocar; las variantes se recortan de él.
 const logo=await page.request.get('/coco-erp-logo.png');expect(crypto.createHash('sha256').update(await logo.body()).digest('hex')).toBe('c3e75d1cbbf288bd180c62593ea5bad31c2678986804e6b053c8f3bc6d675f15');
});
test('customization persists without removing navigation or access to modules',async({page})=>{
 await page.setViewportSize({width:1440,height:900});await boot(page);
 await page.locator('#arcCustomizeOpen').click();await page.locator('#arcCustomize input[value="crm"]').uncheck();await page.locator('#arcCustomize button[value="save"]').click();
 await expect(page.locator('#mainmenu [data-gama-module="crm"]')).toBeHidden();
 await expect(page.locator('.arcNav [data-gama-module="crm"]')).toBeVisible();
 await page.reload();await expect(page.locator('#mainmenu [data-gama-module="crm"]')).toBeHidden();
 await page.locator('#arcCustomizeOpen').click();await page.locator('#arcCustomize button[value="reset"]').click();await expect(page.locator('#mainmenu [data-gama-module="crm"]')).toBeVisible();
});
test('client role has no administrative metrics, notifications or stock activity',async({page})=>{
 await page.setViewportSize({width:1440,height:900});await boot(page,'client');
 await expect(page.locator('#arcNotify')).toBeHidden();await expect(page.locator('#arcRecentActivity')).toHaveCount(0);
 await expect(page.locator('#gamaF2Kpis')).toBeHidden();await expect(page.locator('.arcNav [data-gama-module="assistant-ia"]')).toBeHidden();
 await page.locator('#arcCustomizeOpen').click();await expect(page.locator('#arcCustomize input[value="assistant-ia"]')).toHaveCount(0);
});
test('tablet expands the rail and mobile drawer excludes hidden navigation from keyboard',async({page})=>{
 await page.setViewportSize({width:1024,height:800});await boot(page);
 await expect(page.locator('.arcLogoMark')).toBeVisible();await expect(page.locator('.arcLogo')).toBeHidden();
 await page.locator('.arcBurger').click();await expect(page.locator('.arcNavLabel').first()).toBeVisible();
 await expect(page.locator('.arcLogo')).toBeVisible();await expect(page.locator('.arcLogoMark')).toBeHidden();
 await page.keyboard.press('Escape');await page.setViewportSize({width:390,height:844});await page.waitForTimeout(350);
 expect(await page.locator('.arcSidebar').evaluate(x=>x.inert)).toBe(true);
 await page.locator('.arcBurger').click();expect(await page.locator('.arcSidebar').evaluate(x=>x.inert)).toBe(false);
 await page.locator('.arcNav [data-gama-module="products"]').click();await expect(page.locator('#products')).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBe(0);
});
