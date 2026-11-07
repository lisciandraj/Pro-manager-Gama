const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
const path=require('node:path');

// Exercise the real menu component without making a connection to business data.
async function boot(page,{admin=true,environment='development'}={}){
 await page.route('**/environment-menu-fixture',r=>r.fulfill({contentType:'text/html',body:'<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><main id="mainmenu" class="active"></main></body></html>'}));
 await page.route('**/production/',r=>r.fulfill({contentType:'text/html',body:'<h1>Production release</h1>'}));
 await page.route('**/development/',r=>r.fulfill({contentType:'text/html',body:'<h1>Development release</h1>'}));
 await page.goto('/environment-menu-fixture');
 await page.addStyleTag({content:':root{--arc-text:#283b42;--arc-text-muted:#5f7178;--arc-accent-600:#2f7180;--arc-surface-2:#eef3f4}body{font-family:Arial,sans-serif;margin:14px}*{box-sizing:border-box}'+fs.readFileSync(path.join(__dirname,'../src/styles/home.css'),'utf8')});
 await page.evaluate(({admin,environment})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Forged browser value'}));
  window.__verifiedAdmin=admin;
  window.GamaI18n={language:'fr',t(value){const translations={Producción:{fr:'Production',en:'Production'},Desarrollo:{fr:'Développement',en:'Development'},'Entornos de trabajo':{fr:'Environnements de travail',en:'Work environments'},'Versión:':{fr:'Version :',en:'Version:'}};return translations[value]?.[this.language]||value}};
  window.CocoEnvironment={name:environment,version:'1234567890abcdef1234567890abcdef12345678',url:name=>new URL('/'+name+'/',location.href).href,canDevelop:()=>window.__verifiedAdmin};
  window.ArcModules={groups:['Resumen'],registry:[{id:'products',label:'Productos',icon:'cube',group:'Resumen',menu:true}]};
  window.ArcUI={icons:{},render:(el,html)=>{el.innerHTML=html},moduleIcon:()=>'',esc:value=>String(value).replace(/[&<>"']/g,x=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]))};
  window.ArcRouter={open:()=>Promise.resolve()};window.gamaAccessAllowed=()=>true;
 },{admin,environment});
 await page.addScriptTag({path:path.join(__dirname,'../src/ui/home-menu.js')});
}

test('administrator sees independent release destinations and the current version on desktop and phone',async({page})=>{
 await boot(page);
 const nav=page.getByRole('navigation',{name:'Environnements de travail'});
 await expect(nav.getByRole('link',{name:'Production',exact:true})).toHaveAttribute('href','http://127.0.0.1:4173/production/');
 await expect(nav.getByRole('link',{name:'Développement',exact:true})).toHaveAttribute('aria-current','page');
 await expect(nav.locator('.cocoEnvironmentVersion')).toHaveText('Version : 12345678');
 for(const width of [1440,390,320]){
  await page.setViewportSize({width,height:900});
  await expect(nav).toBeInViewport();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth)).toBe(0);
  for(const link of await nav.getByRole('link').all())expect((await link.boundingBox()).height).toBeGreaterThanOrEqual(44);
 }
 await nav.getByRole('link',{name:'Production',exact:true}).focus();
 await page.keyboard.press('Enter');
 await expect(page).toHaveURL(/\/production\/$/);
 await expect(page.getByRole('heading',{name:'Production release'})).toBeVisible();
});

test('browser role values do not reveal development and verified revocation removes its link',async({page})=>{
 await boot(page,{admin:false,environment:'production'});
 await expect(page.getByRole('link',{name:'Production',exact:true})).toHaveAttribute('aria-current','page');
 await expect(page.getByRole('link',{name:'Développement',exact:true})).toHaveCount(0);
 await page.evaluate(()=>{window.__verifiedAdmin=true;window.dispatchEvent(new CustomEvent('gama:profile-ready'))});
 await expect(page.getByRole('link',{name:'Développement',exact:true})).toBeVisible();
 await page.evaluate(()=>{window.__verifiedAdmin=false;window.dispatchEvent(new CustomEvent('coco:environment-access-change'))});
 await expect(page.getByRole('link',{name:'Développement',exact:true})).toHaveCount(0);
 await expect(page.locator('#mainmenu .gamaF2Card')).toHaveCount(1);
});

test('environment labels follow the selected language without duplicating the navigation',async({page})=>{
 await boot(page);
 await page.evaluate(()=>{window.GamaI18n.language='en';window.dispatchEvent(new CustomEvent('gama:language-change'))});
 await expect(page.getByRole('navigation',{name:'Work environments'})).toHaveCount(1);
 await expect(page.getByRole('link',{name:'Development',exact:true})).toBeVisible();
 await page.getByRole('link',{name:'Development',exact:true}).click();
 await expect(page).toHaveURL(/\/development\/$/);
});
