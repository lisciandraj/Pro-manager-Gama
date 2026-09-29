const {test,expect}=require('@playwright/test');
const fs=require('node:fs'),path=require('node:path');
const MOCK=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const PNG=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4XcAAAAASUVORK5CYII=','base64');
async function boot(page){
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({id:'test-admin-uid',role:'admin',name:'Ana Torres'}));
  window.__DB={products:[],customers:[],suppliers:[],invoices:[],invoice_lines:[],app_modules:[],
   hr_employees:[{id:'e1',full_name:'Ana Torres',profile_id:'test-admin-uid',active:true},{id:'e2',full_name:'Other Person',profile_id:'other-user',active:true}],
   hr_employee_private:[],hr_absences:[],hr_absence_private:[],profiles:[{id:'test-admin-uid',full_name:'Ana Torres',role:'administrador',active:true}],
   _profile:{id:'test-admin-uid',full_name:'Ana Torres',role:'administrador',active:true},_session:{profile_id:'test-admin-uid'}};
 });
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:MOCK}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');
 await expect(page.locator('#arcUserName')).toHaveText('Ana Torres');
}
test('HR uploads, persists, previews and removes the connected employee photo',async({page})=>{
 await boot(page);await expect(page.locator('#arcAvatar')).toHaveText('AT');
 await page.evaluate(()=>window.GamaOpenHR());
 await page.locator('[data-edit="e1"]').click();
 await page.locator('#hrPhoto').setInputFiles({name:'portrait.png',mimeType:'image/png',buffer:PNG});
 await expect(page.locator('#hrPhotoPreview img')).toBeVisible();
 await page.locator('#hrSave').click();
 await expect(page.locator('#arcAvatar img')).toBeVisible();
 const saved=await page.evaluate(()=>window.__DB.hr_employees.find(e=>e.id==='e1').photo_data);
 expect(saved).toMatch(/^data:image\/jpeg;base64,/);expect(saved.length).toBeLessThan(120000);
 await page.locator('[data-edit="e1"]').click();
 await expect(page.locator('#hrPhotoPreview img')).toBeVisible();
 await page.locator('#hrName').fill('Ana Torres Updated');await page.locator('#hrSave').click();
 expect(await page.evaluate(()=>window.__DB.hr_employees.find(e=>e.id==='e1').photo_data)).toBe(saved);
 await page.locator('[data-edit="e1"]').click();await page.locator('#hrPhotoRemove').click();await page.locator('#hrSave').click();
 await expect(page.locator('#arcAvatar img')).toHaveCount(0);await expect(page.locator('#arcAvatar')).toHaveText('AT');
 expect(await page.evaluate(()=>window.__DB.hr_employees.find(e=>e.id==='e1').photo_data)).toBeNull();
});
test('the avatar isolates account changes and falls back for broken images',async({page})=>{
 await boot(page);
 await page.evaluate(async()=>{const c=document.createElement('canvas');c.width=c.height=32;window.__DB.hr_employees[0].photo_data=c.toDataURL('image/png');await window.GamaEmployeePhotos.refresh(true)});
 await expect(page.locator('#arcAvatar img')).toBeVisible();
 await page.evaluate(()=>{window.__DB._session.profile_id='other-user';window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_IN',session:{user:{id:'other-user'}}}}))});
 await expect(page.locator('#arcAvatar img')).toHaveCount(0);
 await page.evaluate(async()=>{window.__DB.hr_employees[1].photo_data='data:image/jpeg;base64,YWJj';await window.GamaEmployeePhotos.refresh(true)});
 await expect(page.locator('#arcAvatar img')).toHaveCount(0);
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT',session:null}})));
 await expect(page.locator('#arcAvatar img')).toHaveCount(0);
});
for(const width of [1440,390])test(`GAMA reference surfaces fit at ${width}px and preserve the top bar`,async({page})=>{
 await page.setViewportSize({width,height:1000});await boot(page);
 await expect(page.locator('.arcSidebar')).toHaveCSS('background-color','rgb(255, 255, 255)');
 await expect(page.locator('#mainmenu .gamaF2Card').first()).toHaveCSS('background-color','rgb(255, 255, 255)');
 const bar=()=>page.evaluate(()=>[...document.querySelectorAll('.arcTopbar,.arcTopbar *')].map(el=>{const s=getComputedStyle(el);return [s.color,s.backgroundColor,s.borderColor,s.borderRadius,s.padding,s.fontSize,s.width,s.height]}));
 const before=await bar();await page.evaluate(()=>document.querySelector('link[href^="gama-design.css"]').disabled=true);
 expect(await bar()).toEqual(before);
 await page.evaluate(()=>document.querySelector('link[href^="gama-design.css"]').disabled=false);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth)).toBe(0);
 await page.screenshot({path:`test-results/gama-menu-${width}.png`,fullPage:true});
 await page.evaluate(()=>window.GamaOpenHR());
 await expect(page.locator('#hrPhoto')).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth)).toBe(0);
 await page.screenshot({path:`test-results/gama-hr-${width}.png`,fullPage:true});
});
